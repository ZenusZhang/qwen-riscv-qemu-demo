# PyTorch RISC-V QEMU Full System Emulation

Complete bootable QEMU RISC-V system with PyTorch libraries for full system emulation.

## Quick Start

### Prerequisites
```bash
# Install required tools (Ubuntu/Debian)
sudo apt-get install -y \
    qemu-system-misc \
    build-essential \
    bison flex bc \
    libssl-dev libelf-dev \
    wget tar cpio gzip git
```

### Automated Build

Use the build script to automatically build everything:

```bash
./build_pytorch_qemu_riscv.sh --pytorch /path/to/pytorch/install
```

This will:
1. Clone and build OpenSBI firmware
2. Clone and build Linux kernel
3. Download Alpine Linux RISC-V rootfs
4. Copy PyTorch libraries
5. Create initramfs
6. Generate QEMU launch script

### Run the System

```bash
./run_qemu.sh
```

Configuration options:
```bash
MEMORY=4G ./run_qemu.sh    # Set memory (default: 2G)
SMP=8 ./run_qemu.sh        # Set CPUs (default: 4)
```

To exit: Press `Ctrl-A` then `X`

## Manual Build

For step-by-step manual instructions, see [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)

## Documentation

- **[BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)** - Complete manual build guide
- **[ALPINE_ROOTFS_SOLUTION.md](ALPINE_ROOTFS_SOLUTION.md)** - Why Alpine Linux was chosen
- **[QWEN_RUN_GUIDE.md](QWEN_RUN_GUIDE.md)** - Running the Qwen3-0.6B PyTorch demo in QEMU
- **[PYTORCH_QEMU_QUICKSTART.md](../PYTORCH_QEMU_QUICKSTART.md)** - Quick start guide

## Project Structure

```
riscv_qemu_demo/
├── build_pytorch_qemu_riscv.sh    # Automated build script
├── run_qemu.sh                     # QEMU launch script
├── BUILD_INSTRUCTIONS.md           # Manual build documentation
├── ALPINE_ROOTFS_SOLUTION.md       # Technical solution details
├── src/
│   ├── opensbi/                    # OpenSBI firmware source
│   └── linux/                      # Linux kernel source
├── build/
│   ├── opensbi/
│   │   └── platform/generic/firmware/
│   │       └── fw_jump.bin         # Bootable firmware (~250KB)
│   └── linux/
│       └── arch/riscv/boot/
│           └── Image               # Kernel image (~22MB)
├── rootfs_alpine/                  # Alpine Linux root filesystem
└── initramfs_alpine.cpio.gz        # Compressed rootfs (~63MB)
```

## System Specifications

- **Architecture:** RISC-V 64-bit (rv64imafdch)
- **Kernel:** Linux 6.10.5
- **Firmware:** OpenSBI v1.7
- **Base System:** Alpine Linux 3.21
- **Memory:** 2GB default (configurable)
- **CPUs:** 4 cores default (configurable)
- **PyTorch:** CPU-only build, dynamically linked

## Key Features

✅ **Full system emulation** - Complete bootable system, not user-mode
✅ **Alpine Linux base** - Lightweight, proven compatibility
✅ **No vector extensions** - Fully compatible with QEMU virt machine
✅ **Complete PyTorch** - All libraries and dependencies included
✅ **Dynamic linking** - Smaller binaries, shared libraries
✅ **Working shell** - Full busybox utilities available
✅ **Configurable** - Adjustable memory and CPU count

## Boot Process

1. **QEMU starts** → Loads OpenSBI firmware
2. **OpenSBI initializes** → Platform setup (UART, timer, IPI)
3. **OpenSBI boots kernel** → Jump to Linux 6.10.5
4. **Kernel mounts rootfs** → Unpack initramfs to memory
5. **Init script runs** → Mount /proc, /sys, /dev
6. **Shell prompt** → System ready for use

## Successful Boot Example

```
OpenSBI v1.7
Platform Name: riscv-virtio,qemu
Platform HART Count: 4
Boot HART ISA: rv64imafdch

Linux version 6.10.5
...
Freeing initrd memory: 64056K
Run /init as init process

==========================================
PyTorch RISC-V QEMU System (Alpine Linux)
==========================================

Checking PyTorch libraries...
✓ PyTorch libraries found in /usr/local/lib/
-rw-r--r--    1 root     root        1.6M libtorch.so
-rw-r--r--    1 root     root      149.5M libtorch_cpu.so
-rw-r--r--    1 root     root        7.2K libtorch_global_deps.so

System ready. Dropping to shell...
~ #
```

## Troubleshooting

### Build fails with "command not found"
Install missing dependencies (see Prerequisites section)

### Illegal instruction error during boot
This shouldn't happen with Alpine Linux. If it does, verify you're using the Alpine rootfs, not a custom-built busybox.

### PyTorch libraries not found in booted system
Ensure `--pytorch` path points to a valid PyTorch installation with `lib/*.so` files.

### QEMU doesn't start
Check that `qemu-system-riscv64` is installed:
```bash
which qemu-system-riscv64
# If not found:
sudo apt-get install qemu-system-misc
```

## Development

### Adding Files to Rootfs

```bash
# Add files to rootfs_alpine/
cp my_app rootfs_alpine/usr/local/bin/

# Rebuild initramfs
cd rootfs_alpine
find . -print0 | cpio --null --create --format=newc | gzip -9 > ../initramfs_alpine.cpio.gz
cd ..

# Boot with new initramfs
./run_qemu.sh
```

### Testing PyTorch Applications

```bash
# Copy your PyTorch C++ application
cp my_pytorch_app rootfs_alpine/usr/local/bin/

# Rebuild initramfs (see above)

# Boot and run
./run_qemu.sh
# Inside QEMU:
~ # /usr/local/bin/my_pytorch_app
```

## Distribution

To create a distributable package:

```bash
cd ..
tar czf pytorch-qemu-riscv64.tar.gz \
    riscv_qemu_demo/build/opensbi/platform/generic/firmware/fw_jump.bin \
    riscv_qemu_demo/build/linux/arch/riscv/boot/Image \
    riscv_qemu_demo/initramfs_alpine.cpio.gz \
    riscv_qemu_demo/run_qemu.sh \
    riscv_qemu_demo/*.md
```

Package size: ~85MB

To use on another machine:
```bash
tar xzf pytorch-qemu-riscv64.tar.gz
cd riscv_qemu_demo
./run_qemu.sh
```

## Technical Notes

### Why Alpine Linux?

Alpine Linux provides pre-built RISC-V binaries compiled without vector extensions, ensuring compatibility with QEMU's virt machine. Custom-built busybox from source tends to include vector extensions that QEMU doesn't support by default.

See [ALPINE_ROOTFS_SOLUTION.md](ALPINE_ROOTFS_SOLUTION.md) for detailed explanation.

### ISA Compatibility

- **QEMU virt machine:** Supports rv64gc + Zicntr, Zihpm, Zicboz, Zicbom, etc.
- **Alpine busybox:** Built with rv64imafdc (no vector extensions)
- **Linux kernel:** Compiled for rv64imafdch with common extensions

All components are ISA-compatible with each other.

## References

- [OpenSBI Documentation](https://github.com/riscv-software-src/opensbi)
- [Linux RISC-V](https://www.kernel.org/doc/html/latest/riscv/index.html)
- [Alpine Linux RISC-V](https://alpinelinux.org/downloads/)
- [QEMU RISC-V System Emulation](https://www.qemu.org/docs/master/system/target-riscv.html)
- [PyTorch](https://pytorch.org/)

## License

This build system follows the licenses of its components:
- OpenSBI: BSD 2-Clause License
- Linux kernel: GNU General Public License v2.0
- Alpine Linux: Various open source licenses
- PyTorch: BSD-style License

## Support

For issues or questions:
1. Check [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) troubleshooting section
2. Review [ALPINE_ROOTFS_SOLUTION.md](ALPINE_ROOTFS_SOLUTION.md) for technical details
3. Verify all prerequisites are installed
4. Check that RISC-V toolchain and PyTorch paths are correct
