# Master Index - PyTorch RISC-V QEMU Build System

Complete reproduction package for building a bootable QEMU RISC-V system with PyTorch.

## 📋 Document Guide

Start here based on your needs:

| Document | Purpose | When to Use |
|----------|---------|-------------|
| **[README.md](README.md)** | Project overview & quick start | First time users, want quick overview |
| **[REPRODUCTION_GUIDE.md](REPRODUCTION_GUIDE.md)** | Complete setup guide | Setting up on new machine |
| **[BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)** | Detailed manual build | Want to understand each step, debugging |
| **[ALPINE_ROOTFS_SOLUTION.md](ALPINE_ROOTFS_SOLUTION.md)** | Technical details | Understanding design decisions |

## 🚀 Quick Start

**For first-time users:**
1. Read [README.md](README.md) - 5 minutes
2. Follow [REPRODUCTION_GUIDE.md](REPRODUCTION_GUIDE.md) - Complete setup

**For experienced users:**
```bash
./build_pytorch_qemu_riscv.sh --pytorch /path/to/pytorch/install
./run_qemu.sh
```

## 📦 Package Contents

### Core Files (6 total)

#### Documentation (4 files, ~30KB)
- `README.md` - Main overview
- `REPRODUCTION_GUIDE.md` - Setup instructions
- `BUILD_INSTRUCTIONS.md` - Detailed manual build
- `ALPINE_ROOTFS_SOLUTION.md` - Technical explanation

#### Scripts (2 files, ~15KB)
- `build_pytorch_qemu_riscv.sh` - Automated build (MAIN SCRIPT)
- `run_qemu.sh` - QEMU launcher

### Generated Files (after build)
- `build/opensbi/.../fw_jump.bin` - OpenSBI firmware (~250KB)
- `build/linux/.../Image` - Linux kernel (~22MB)
- `initramfs_alpine.cpio.gz` - Root filesystem (~63MB)
- `rootfs_alpine/` - Extracted Alpine Linux

## 🎯 What This Builds

A complete bootable RISC-V system with:
- ✅ OpenSBI v1.7 firmware
- ✅ Linux kernel 6.10.5
- ✅ Alpine Linux 3.21 userspace
- ✅ PyTorch libraries (libtorch, libtorch_cpu, libc10)
- ✅ All system dependencies
- ✅ Working shell and utilities

## 🔧 System Requirements

**Minimum:**
- 2GB RAM
- 5GB disk space
- 2 CPU cores
- Ubuntu 20.04+ or Debian 11+

**Recommended:**
- 8GB RAM
- 10GB disk space
- 4+ CPU cores

**Required Software:**
- RISC-V cross-compilation toolchain
- QEMU system emulator
- Standard build tools (make, gcc, git, etc.)

## ⚡ Build Process Overview

```
1. Prerequisites Installation      (5 min)
   ↓
2. Clone OpenSBI & Linux           (5-10 min)
   ↓
3. Build OpenSBI Firmware          (1-2 min)
   ↓
4. Build Linux Kernel              (10-30 min)
   ↓
5. Prepare Alpine Rootfs           (2 min)
   ↓
6. Copy PyTorch Libraries          (1 min)
   ↓
7. Create Initramfs                (2 min)
   ↓
8. Generate Launch Script          (instant)
   ↓
TOTAL: 15-40 minutes
```

## 📖 Documentation Breakdown

### README.md (7KB) - START HERE
- Project overview
- Quick start guide
- Configuration options
- Common issues
- Development tips

**Read if:** You're new to the project

### REPRODUCTION_GUIDE.md (8KB) - SETUP GUIDE
- Detailed prerequisites
- Step-by-step setup
- Command examples
- Troubleshooting
- Distribution options

**Read if:** Setting up on a new machine

### BUILD_INSTRUCTIONS.md (11KB) - REFERENCE
- Complete manual build steps
- Technical explanations
- Configuration details
- File sizes and locations
- Kernel configuration

**Read if:** You want to build manually or debug issues

### ALPINE_ROOTFS_SOLUTION.md (3KB) - TECHNICAL
- Why Alpine Linux was chosen
- Vector extension compatibility
- Alternative approaches tried
- ISA compatibility details

**Read if:** You want to understand technical decisions

## 🛠️ Script Usage

### build_pytorch_qemu_riscv.sh - Main Build Script

**Basic usage:**
```bash
./build_pytorch_qemu_riscv.sh --pytorch /path/to/pytorch/install
```

**All options:**
```bash
./build_pytorch_qemu_riscv.sh \
  --pytorch /path/to/pytorch/install \
  --toolchain /path/to/riscv/toolchain \
  --jobs 8 \
  --clean
```

**What it does:**
1. Validates prerequisites
2. Clones source repositories
3. Builds OpenSBI firmware
4. Configures and builds Linux kernel
5. Downloads Alpine Linux rootfs
6. Copies PyTorch libraries
7. Creates bootable initramfs
8. Generates QEMU launch script

**Output:** Complete bootable system in current directory

### run_qemu.sh - Launch Script

**Basic usage:**
```bash
./run_qemu.sh
```

**With options:**
```bash
MEMORY=4G SMP=8 ./run_qemu.sh
```

**What it does:**
- Validates all required files exist
- Launches QEMU with proper configuration
- Boots into Alpine Linux + PyTorch

**To exit:** Press `Ctrl-A` then `X`

## 🎓 Learning Path

### Beginner
1. Start with [README.md](README.md)
2. Run `./build_pytorch_qemu_riscv.sh --pytorch PATH`
3. Boot with `./run_qemu.sh`
4. Explore the booted system

### Intermediate
1. Read [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)
2. Try manual build steps
3. Customize kernel configuration
4. Add your own applications

### Advanced
1. Study [ALPINE_ROOTFS_SOLUTION.md](ALPINE_ROOTFS_SOLUTION.md)
2. Modify build scripts
3. Experiment with different kernel versions
4. Create optimized configurations

## 🔍 Troubleshooting

**Build fails?**
→ Check [REPRODUCTION_GUIDE.md](REPRODUCTION_GUIDE.md) troubleshooting section

**QEMU won't start?**
→ See [README.md](README.md) troubleshooting section

**Want to understand why?**
→ Read [ALPINE_ROOTFS_SOLUTION.md](ALPINE_ROOTFS_SOLUTION.md)

**Need detailed steps?**
→ Follow [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)

## 📦 Distribution Options

### Complete Package (includes binaries)
```bash
tar czf pytorch-qemu-riscv64.tar.gz riscv_qemu_demo/
# Size: ~85MB
```

### Scripts Only
```bash
tar czf pytorch-qemu-scripts.tar.gz *.md *.sh
# Size: ~45KB
```

### Minimal Runtime (ready to boot)
```bash
tar czf pytorch-qemu-minimal.tar.gz \
    build/opensbi/.../fw_jump.bin \
    build/linux/.../Image \
    initramfs_alpine.cpio.gz \
    run_qemu.sh
# Size: ~85MB, no build capability
```

## ✅ Success Indicators

You've successfully completed the build when:
1. ✅ Build script finishes without errors
2. ✅ All three binaries exist (firmware, kernel, initramfs)
3. ✅ `./run_qemu.sh` boots successfully
4. ✅ You see "PyTorch RISC-V QEMU System" banner
5. ✅ PyTorch libraries are detected
6. ✅ Shell prompt appears

## 🎯 Next Steps After Building

1. **Test PyTorch**: Try loading models, running inference
2. **Benchmark**: Test performance on RISC-V
3. **Develop**: Create C++ applications using PyTorch
4. **Package**: Create distributable systems for others
5. **Customize**: Modify kernel, add packages, optimize

## 📚 External References

- **RISC-V Toolchain**: https://github.com/riscv-collab/riscv-gnu-toolchain
- **OpenSBI**: https://github.com/riscv-software-src/opensbi
- **Linux Kernel**: https://kernel.org
- **Alpine Linux**: https://alpinelinux.org/downloads/
- **QEMU**: https://www.qemu.org/docs/master/system/target-riscv.html
- **PyTorch**: https://pytorch.org

## 🤝 Support

For issues:
1. Check relevant documentation file
2. Review troubleshooting sections
3. Verify all prerequisites installed
4. Check toolchain and PyTorch paths

## 📄 License

This build system follows component licenses:
- OpenSBI: BSD 2-Clause
- Linux: GPLv2
- Alpine Linux: Various OSI licenses
- PyTorch: BSD-style

---

**Ready to start?** → Begin with [README.md](README.md)

**Need help?** → Check [REPRODUCTION_GUIDE.md](REPRODUCTION_GUIDE.md)

**Want details?** → Read [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)
