# Agents Activity Log

I'm working for writing pytorch aten kernels for riscv vector isa.
This repo is to build workload by pytorch that would run on qemu-system.
The overall step is:
Firstly building the pytorch shared libs.
Secondly building the sys packages.
Thirdly run the workload into pytorch.

In this period, we'd like to run qwen model by pytorch with only 1 input token and 1 output token.

# status (you should update when you have process)
Till now, we can build the pytorch and sys packages and can boot qemu successfully.
What we should do is to run qwen by pytorch in qemu env.

## 2025-10-16
- Added `repros_protoc_exec_format.sh` to capture the `protoc` Exec format regression and verified it failed before fixes.
- Updated `build_pytorch_riscv.sh` to force a host-native protobuf toolchain and clean the stale build tree before regenerating `protoc`.
- Rebuilt protobuf with the new settings and confirmed `protoc --version` runs successfully on x86_64.
- After each modification, commit and push the code using gh.
- Ran the Qwen3 demo end-to-end in QEMU after repacking the initramfs with toolchain sysroot libraries and taught `build_pytorch_qemu_riscv.sh` to stage those libs automatically.
- Hardened the protobuf stage to reuse only host-runnable `protoc` binaries and fall back to rebuilding with explicit host compilers when a stale RISC-V executable is detected.
