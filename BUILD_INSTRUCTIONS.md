# PyTorch RISC-V QEMU Full System Build Instructions

## Overview

This document provides complete instructions to build a bootable QEMU RISC-V system with PyTorch libraries and all dependencies for full system emulation.

## Prerequisites

### Required Tools
- RISC-V cross-compilation toolchain (GCC 14.2.0 or later)
- QEMU system emulator for RISC-V (`qemu-system-riscv64`)
- Standard build tools: make, gcc, bison, flex, bc, libssl-dev, libelf-dev
- wget, tar, cpio, gzip

### Installation on Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y \
    qemu-system-misc \
    build-essential \
    bison flex bc \
    libssl-dev libelf-dev \
    wget tar cpio gzip \
    git
```

### RISC-V Toolchain
Download from: https://github.com/riscv-collab/riscv-gnu-toolchain/releases
Or use existing toolchain at: `/workspace/riscv64-unknown-linux_gnu_14.2.0/`

## Project Structure

```
pytorch/riscv_qemu_demo/
├── src/
│   ├── opensbi/          # OpenSBI firmware source
│   └── linux/            # Linux kernel source
├── build/
│   ├── opensbi/
│   │   └── platform/generic/firmware/
│   │       └── fw_jump.bin        # Bootable firmware
│   └── linux/
│       └── arch/riscv/boot/
│           └── Image              # Kernel image
├── rootfs_alpine/        # Alpine Linux root filesystem
├── initramfs_alpine.cpio.gz      # Compressed rootfs
└── run_qemu.sh           # QEMU launch script
```

## Build Steps

### Step 1: Clone and Prepare Sources

```bash
cd /root/pytorch
mkdir -p riscv_qemu_demo/src
cd riscv_qemu_demo/src

# Clone OpenSBI
git clone https://github.com/riscv-software-src/opensbi.git
cd opensbi
git checkout v1.7
cd ..

# Clone Linux kernel
git clone --depth 1 --branch v6.10.5 https://github.com/torvalds/linux.git
cd ..
```

### Step 2: Build OpenSBI Firmware

```bash
cd src/opensbi
export CROSS_COMPILE=/workspace/riscv64-unknown-linux_gnu_14.2.0/bin/riscv64-unknown-linux-gnu-
export PLATFORM=generic

make PLATFORM=generic CROSS_COMPILE=$CROSS_COMPILE \
    O=../../build/opensbi

# Verify firmware was built
ls -lh ../../build/opensbi/platform/generic/firmware/fw_jump.bin
```

Expected output: `fw_jump.bin` (~250KB)

### Step 3: Configure and Build Linux Kernel

```bash
cd ../linux

# Create default RISC-V config
make ARCH=riscv CROSS_COMPILE=$CROSS_COMPILE \
    O=../../build/linux defconfig

# Important: Disable embedded initramfs
cd ../../build/linux
sed -i 's/CONFIG_INITRAMFS_SOURCE=.*/CONFIG_INITRAMFS_SOURCE=""/' .config

# Build kernel
cd ../../src/linux
make ARCH=riscv CROSS_COMPILE=$CROSS_COMPILE \
    O=../../build/linux -j$(nproc)

# Verify kernel was built
ls -lh ../../build/linux/arch/riscv/boot/Image
```

Expected output: `Image` (~22MB)

### Step 4: Create Root Filesystem with Alpine Linux

Alpine Linux provides pre-built RISC-V root filesystems that are compatible with QEMU (no vector extension issues).

```bash
cd /root/pytorch/riscv_qemu_demo

# Download Alpine RISC-V minirootfs
mkdir -p rootfs_alpine
cd rootfs_alpine
wget https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/riscv64/alpine-minirootfs-3.21.0-riscv64.tar.gz

# Extract
tar xzf alpine-minirootfs-3.21.0-riscv64.tar.gz
rm alpine-minirootfs-3.21.0-riscv64.tar.gz

cd ..
```

### Step 5: Copy PyTorch Libraries

Assuming you have PyTorch built for RISC-V:

```bash
# Create library directories
mkdir -p rootfs_alpine/usr/local/lib

# Copy PyTorch libraries
# Source: your PyTorch build output directory
PYTORCH_INSTALL=/path/to/pytorch/install

cp -r $PYTORCH_INSTALL/lib/*.so* rootfs_alpine/usr/local/lib/

# Copy system libraries (glibc, libstdc++, etc.) from toolchain
TOOLCHAIN_LIBS=/workspace/riscv64-unknown-linux_gnu_14.2.0/sysroot/lib64/lp64d
cp -r $TOOLCHAIN_LIBS/* rootfs_alpine/lib/

# Or if you have pre-built libs in rootfs_minimal:
# cp -r rootfs_minimal/usr/local/lib/* rootfs_alpine/usr/local/lib/
# cp -r rootfs_minimal/lib/* rootfs_alpine/lib/
```

Libraries needed:
- `libtorch.so`, `libtorch_cpu.so`, `libc10.so`
- `libonnx.so`, `libprotobuf.so`
- `libgcc_s.so`, `libstdc++.so`, `libgomp.so`
- Standard C library (libc, libm, libdl, etc.)

### Step 6: Create Init Script

```bash
cat > rootfs_alpine/init << 'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs devtmpfs /dev

echo ""
echo "=========================================="
echo "PyTorch RISC-V QEMU System (Alpine Linux)"
echo "=========================================="
echo ""
echo "Checking PyTorch libraries..."
export LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH:-}

if [ -f /usr/local/lib/libtorch.so ]; then
  echo "✓ PyTorch libraries found in /usr/local/lib/"
  ls -lh /usr/local/lib/libtorch*.so 2>/dev/null || true
else
  echo "✗ PyTorch libraries NOT found"
fi

echo ""
echo "System ready. Dropping to shell..."
echo ""

exec /bin/sh
EOF

chmod +x rootfs_alpine/init
```

### Step 7: Create Initramfs

```bash
cd rootfs_alpine
find . -print0 | cpio --null --create --format=newc | gzip -9 > ../initramfs_alpine.cpio.gz
cd ..

# Verify size
ls -lh initramfs_alpine.cpio.gz
```

Expected output: ~63MB compressed

### Step 8: Create QEMU Launch Script

```bash
cat > run_qemu.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT=$(realpath "$(dirname "$0")")
BIOS="$ROOT/build/opensbi/platform/generic/firmware/fw_jump.bin"
KERNEL="$ROOT/build/linux/arch/riscv/boot/Image"
INITRAMFS="$ROOT/initramfs_alpine.cpio.gz"
MEM=${MEMORY:-2G}
SMP=${SMP:-4}

if [ ! -f "$BIOS" ]; then
  echo "OpenSBI firmware not found at $BIOS" >&2
  exit 1
fi

if [ ! -f "$KERNEL" ]; then
  echo "Kernel image not found at $KERNEL" >&2
  exit 1
fi

if [ ! -f "$INITRAMFS" ]; then
  echo "Initramfs not found at $INITRAMFS" >&2
  exit 1
fi

echo "Starting QEMU RISC-V system..."
echo "  Firmware: $BIOS"
echo "  Kernel:   $KERNEL"
echo "  Initramfs: $INITRAMFS"
echo "  Memory: $MEM"
echo "  CPUs: $SMP"
echo ""
echo "To exit QEMU, press Ctrl-A then X"
echo ""

exec qemu-system-riscv64 \
  -machine virt \
  -m "$MEM" \
  -smp "$SMP" \
  -nographic \
  -bios "$BIOS" \
  -kernel "$KERNEL" \
  -initrd "$INITRAMFS" \
  -append "console=ttyS0 earlycon=sbi root=/dev/ram0 rw"
EOF

chmod +x run_qemu.sh
```

### Step 9: Test Boot

```bash
./run_qemu.sh
```

Expected output:
```
OpenSBI v1.7
Platform: riscv-virtio,qemu
Boot HART ID: 0
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

System ready. Dropping to shell...
~ #
```

To exit QEMU: Press `Ctrl-A` then `X`

## Configuration Options

### Memory and CPU Count

```bash
# Set memory (default: 2G)
MEMORY=4G ./run_qemu.sh

# Set CPU count (default: 4)
SMP=8 ./run_qemu.sh

# Combine settings
MEMORY=4G SMP=8 ./run_qemu.sh
```

### Kernel Configuration

To customize the kernel (before building):
```bash
cd build/linux
make ARCH=riscv CROSS_COMPILE=$CROSS_COMPILE menuconfig
cd ../../src/linux
make ARCH=riscv CROSS_COMPILE=$CROSS_COMPILE O=../../build/linux -j$(nproc)
```

## Troubleshooting

### Issue: Illegal Instruction Error

**Symptom**: `unhandled signal 4 code 0x1` during boot

**Cause**: Busybox compiled with RISC-V Vector extensions that QEMU doesn't support

**Solution**: Use Alpine Linux rootfs (as documented above). Alpine's busybox is built without vector extensions.

### Issue: Kernel Too Large

**Symptom**: OpenSBI fails to load kernel, or "regions overlapping" error

**Cause**: Kernel has embedded initramfs configured

**Solution**: Ensure `CONFIG_INITRAMFS_SOURCE=""` in kernel `.config`

### Issue: PyTorch Libraries Not Found

**Symptom**: `libXXX.so: cannot open shared object file`

**Cause**: Missing system libraries or wrong paths

**Solution**:
1. Verify libraries are in `/usr/local/lib/` in rootfs
2. Check `LD_LIBRARY_PATH` is set in init script
3. Ensure all dependencies copied from toolchain sysroot

### Issue: OpenSBI Firmware Not Found

**Symptom**: QEMU fails to start

**Cause**: Wrong firmware path or build failed

**Solution**:
1. Check `build/opensbi/platform/generic/firmware/fw_jump.bin` exists
2. Rebuild OpenSBI if missing
3. Verify `CROSS_COMPILE` path is correct

## File Sizes Reference

After successful build:
- OpenSBI firmware: ~250 KB
- Linux kernel: ~22 MB
- Initramfs (Alpine + PyTorch): ~63 MB compressed
- Total package size: ~85 MB

## Distribution

To create a distributable package:

```bash
cd /root/pytorch
tar czf pytorch-qemu-riscv64.tar.gz \
  riscv_qemu_demo/build/opensbi/platform/generic/firmware/fw_jump.bin \
  riscv_qemu_demo/build/linux/arch/riscv/boot/Image \
  riscv_qemu_demo/initramfs_alpine.cpio.gz \
  riscv_qemu_demo/run_qemu.sh \
  riscv_qemu_demo/BUILD_INSTRUCTIONS.md
```

## Key Technical Details

### ISA Compatibility

- **Kernel**: rv64imafdch (with Zicntr, Zihpm, Zicboz, Zicbom, Sdtrig, Svadu)
- **Alpine busybox**: rv64imafdc (no vector extensions)
- **QEMU virt machine**: Supports up to rv64gc + common extensions

### Why Alpine Linux?

Alpine's pre-built RISC-V binaries are:
1. Compiled without vector extensions (compatible with QEMU)
2. Well-tested on RISC-V hardware and emulation
3. Lightweight and complete
4. Regularly updated and maintained

Alternative approaches (busybox from source, Debian debootstrap) require more complex toolchain configuration to avoid vector extension issues.

## Next Steps

1. Test PyTorch functionality inside QEMU
2. Add Python interpreter if needed
3. Create test programs using PyTorch C++ API
4. Build more complete rootfs with package manager

## References

- OpenSBI: https://github.com/riscv-software-src/opensbi
- Linux kernel: https://www.kernel.org/
- Alpine Linux RISC-V: https://alpinelinux.org/downloads/
- QEMU RISC-V: https://www.qemu.org/docs/master/system/target-riscv.html
- PyTorch: https://pytorch.org/

## License

This build system follows the licenses of its components:
- OpenSBI: BSD 2-Clause
- Linux kernel: GPLv2
- Alpine Linux: Various (GPL, MIT, etc.)
- PyTorch: BSD-style license
