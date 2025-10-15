#include <torch/script.h>
#include <torch/csrc/autograd/profiler.h>

#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace {
std::vector<int64_t> load_tokens(const std::string& path) {
  std::ifstream stream(path);
  if (!stream.is_open()) {
    throw std::runtime_error("Failed to open tokens file: " + path);
  }
  std::vector<int64_t> tokens;
  std::string line;
  while (std::getline(stream, line)) {
    std::istringstream line_stream(line);
    int64_t value;
    while (line_stream >> value) {
      tokens.push_back(value);
    }
  }
  if (tokens.empty()) {
    throw std::runtime_error("Token file is empty: " + path);
  }
  return tokens;
}

void write_tokens(const std::vector<int64_t>& tokens, const std::string& path) {
  std::ofstream out(path);
  if (!out.is_open()) {
    throw std::runtime_error("Failed to open output file: " + path);
  }
  for (size_t i = 0; i < tokens.size(); ++i) {
    out << tokens[i];
    if (i + 1 < tokens.size()) {
      out << ' ';
    }
  }
  out << '\n';
}

struct KernelStat {
  double total_us = 0.0;
  double self_us = 0.0;
  double max_us = 0.0;
  int64_t calls = 0;
  std::string sample_shape;
};

std::string format_shape(const std::vector<std::vector<int64_t>>& shapes) {
  if (shapes.empty() || shapes.front().empty()) {
    return "";
  }
  std::ostringstream oss;
  oss << '[';
  const auto& dims = shapes.front();
  for (size_t i = 0; i < dims.size(); ++i) {
    if (i != 0) {
      oss << 'x';
    }
    oss << dims[i];
  }
  oss << ']';
  return oss.str();
}

void aggregate_kernel_stats(
    const torch::autograd::profiler::thread_event_lists& event_lists,
    std::unordered_map<std::string, KernelStat>& stats) {
  using torch::autograd::profiler::EventKind;
  using torch::autograd::profiler::LegacyEvent;

  struct ActiveRange {
    const LegacyEvent* start;
    double child_time_us = 0.0;
  };

  for (const auto& thread_events : event_lists) {
    std::vector<ActiveRange> stack;
    stack.reserve(thread_events.size());
    for (const auto& event : thread_events) {
      if (event.kind() == EventKind::PushRange) {
        stack.push_back({&event, 0.0});
      } else if (event.kind() == EventKind::PopRange) {
        if (stack.empty()) {
          continue;
        }
        ActiveRange active = stack.back();
        stack.pop_back();
        double inclusive_us = active.start->cpuElapsedUs(event);
        if (inclusive_us < 0.0) {
          inclusive_us = 0.0;
        }
        double exclusive_us = inclusive_us - active.child_time_us;
        if (exclusive_us < 0.0) {
          exclusive_us = 0.0;
        }

        const std::string kernel_name(active.start->name());
        KernelStat& stat = stats[kernel_name];
        stat.calls += 1;
        stat.total_us += inclusive_us;
        stat.self_us += exclusive_us;
        stat.max_us = std::max(stat.max_us, inclusive_us);
        if (stat.sample_shape.empty()) {
          stat.sample_shape = format_shape(active.start->shapes());
        }

        if (!stack.empty()) {
          stack.back().child_time_us += inclusive_us;
        }
      }
    }
  }
}

void print_kernel_stats(const std::unordered_map<std::string, KernelStat>& stats) {
  if (stats.empty()) {
    std::cout << "No profiler events collected." << std::endl;
    return;
  }

  std::vector<std::pair<std::string, KernelStat>> ordered(stats.begin(), stats.end());
  std::sort(ordered.begin(), ordered.end(), [](const auto& lhs, const auto& rhs) {
    return lhs.second.total_us > rhs.second.total_us;
  });

  double total_time = 0.0;
  for (const auto& entry : ordered) {
    total_time += entry.second.self_us;
  }

  std::cout << "\nKernel CPU time summary (top 30 by inclusive time)" << std::endl;
  std::cout << std::left << std::setw(48) << "Kernel"
            << std::right << std::setw(10) << "Calls"
            << std::setw(14) << "Total(us)"
            << std::setw(14) << "Self(us)"
            << std::setw(12) << "Avg(us)"
            << std::setw(12) << "Max(us)"
            << std::setw(16) << "Shape" << std::endl;
  std::cout << std::string(126, '-') << std::endl;

  const size_t limit = std::min<size_t>(30, ordered.size());
  for (size_t i = 0; i < limit; ++i) {
    const auto& [name, stat] = ordered[i];
    const double avg_us = stat.calls > 0 ? stat.total_us / static_cast<double>(stat.calls) : 0.0;
    std::cout << std::left << std::setw(48) << name.substr(0, 48)
              << std::right << std::setw(10) << stat.calls
              << std::setw(14) << std::fixed << std::setprecision(2) << stat.total_us
              << std::setw(14) << stat.self_us
              << std::setw(12) << avg_us
              << std::setw(12) << stat.max_us
              << std::setw(16)
              << (stat.sample_shape.empty() ? "" : stat.sample_shape) << std::endl;
  }

  std::cout << std::string(126, '-') << std::endl;
  std::cout << "Self time total: " << std::fixed << std::setprecision(2) << total_time
            << " us" << std::endl;
}
}  // namespace

int main(int argc, const char* argv[]) {
  if (argc < 4) {
    std::cerr << "Usage: " << argv[0]
              << " <torchscript_model> <input_tokens.txt> <output_tokens.txt> [max_new_tokens] [eos_token]" << std::endl;
    return 1;
  }

  const std::string model_path = argv[1];
  const std::string input_tokens_path = argv[2];
  const std::string output_tokens_path = argv[3];
  const int max_new_tokens = argc >= 5 ? std::stoi(argv[4]) : 64;
  const int64_t eos_token = argc >= 6 ? std::stoll(argv[5]) : -1;

  try {
    std::vector<int64_t> prompt_tokens = load_tokens(input_tokens_path);

    torch::jit::Module module = torch::jit::load(model_path);
    module.eval();

    torch::NoGradGuard guard;
    torch::autograd::profiler::thread_event_lists profiler_events;

    torch::profiler::impl::ProfilerConfig profiler_cfg(
        torch::autograd::profiler::ProfilerState::CPU,
        /*report_input_shapes=*/true,
        /*profile_memory=*/false,
        /*with_stack=*/false,
        /*with_flops=*/false,
        /*with_modules=*/false);

    {
      torch::autograd::profiler::TLSLegacyProfilerGuard profiler_guard(
          profiler_cfg,
          [&](const torch::autograd::profiler::thread_event_lists& lists) {
            profiler_events = lists;
          });

      torch::Tensor input = torch::tensor(
                                  prompt_tokens,
                                  torch::TensorOptions().dtype(torch::kLong))
                                 .unsqueeze(0);
      torch::Tensor attention_mask = torch::ones_like(input);

      for (int step = 0; step < max_new_tokens; ++step) {
        std::vector<torch::jit::IValue> inputs;
        inputs.emplace_back(input);
        inputs.emplace_back(attention_mask);
        torch::Tensor logits = module.forward(inputs).toTensor();
        torch::Tensor logits_last = logits.index({0, -1});
        torch::Tensor next_token_tensor = logits_last.argmax().toType(torch::kLong);
        int64_t next_token = next_token_tensor.item<int64_t>();

        input = torch::cat({input, next_token_tensor.view({1, 1})}, 1);
        attention_mask = torch::cat(
            {attention_mask, torch::ones({1, 1}, attention_mask.options())}, 1);
        prompt_tokens.push_back(next_token);
        if (eos_token >= 0 && next_token == eos_token) {
          break;
        }
      }
    }

    write_tokens(prompt_tokens, output_tokens_path);
    std::cout << "Generated " << prompt_tokens.size() << " tokens." << std::endl;

    if (!profiler_events.empty()) {
      std::unordered_map<std::string, KernelStat> kernel_stats;
      aggregate_kernel_stats(profiler_events, kernel_stats);
      print_kernel_stats(kernel_stats);
    } else {
      std::cout << "Profiler did not capture any events." << std::endl;
    }
  } catch (const c10::Error& error) {
    std::cerr << "libtorch error: " << error.msg() << std::endl;
    return 2;
  } catch (const std::exception& ex) {
    std::cerr << "Error: " << ex.what() << std::endl;
    return 3;
  }

  return 0;
}
