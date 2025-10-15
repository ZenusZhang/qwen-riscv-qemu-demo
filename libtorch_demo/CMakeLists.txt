cmake_minimum_required(VERSION 3.18 FATAL_ERROR)
project(qwen3_infer LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_PREFIX_PATH)
  if(DEFINED ENV{TORCH_INSTALL_PREFIX})
    set(CMAKE_PREFIX_PATH "$ENV{TORCH_INSTALL_PREFIX}")
  endif()
endif()

find_package(Torch REQUIRED)

# Ensure dependent shared libs (protobuf/onnx) are linked for cross builds.
set(_TORCH_LIB_SEARCH_DIR "")
foreach(lib ${TORCH_LIBRARIES})
  if (IS_ABSOLUTE "${lib}")
    get_filename_component(_TORCH_LIB_SEARCH_DIR "${lib}" DIRECTORY)
    break()
  endif()
endforeach()

if (_TORCH_LIB_SEARCH_DIR)
  foreach(dep_lib IN ITEMS libprotobuf.so libprotobuf-lite.so libonnx.so libonnx_proto.so libprotoc.so)
    if (EXISTS "${_TORCH_LIB_SEARCH_DIR}/${dep_lib}")
      list(APPEND TORCH_LIBRARIES "${_TORCH_LIB_SEARCH_DIR}/${dep_lib}")
    endif()
  endforeach()
endif()

add_executable(qwen3_infer qwen3_infer.cpp)
target_link_libraries(qwen3_infer torch ${TORCH_LIBRARIES})

if (UNIX)
  target_link_libraries(qwen3_infer pthread)
endif()
