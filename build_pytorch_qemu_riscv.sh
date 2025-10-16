#!/usr/bin/env bash
#
# build_pytorch_qemu_riscv.sh
#
# Automated build script for PyTorch RISC-V QEMU full system emulation
# This script builds OpenSBI firmware, Linux kernel, and creates a bootable
# Alpine Linux-based root filesystem with PyTorch libraries.
#
# Prerequisites:
#   - RISC-V cross-compilation toolchain
#   - QEMU system emulator for RISC-V
#   - Standard build tools (make, gcc, wget, cpio, etc.)
#
# Usage:
#   ./build_pytorch_qemu_riscv.sh [OPTIONS]
#
# Options:
#   --toolchain PATH           Path to RISC-V toolchain (default: /workspace/riscv64-unknown-linux_gnu_14.2.0)
#   --pytorch PATH             Path to PyTorch install directory (set automatically when --build-pytorch is used)
#   --build-pytorch            Build PyTorch for riscv64 using build_pytorch_riscv.sh
#   --pytorch-source PATH      Optional PyTorch source directory for the build step
#   --pytorch-branch REF       Git branch/tag/commit to checkout when building PyTorch
#   --pytorch-clone-url URL    Alternate PyTorch remote when cloning
#   --jobs N                   Number of parallel build jobs (default: nproc)
#   --clean                    Clean build directories before building
#   --help                     Show this help message
#

set -euo pipefail

# Default configuration
TOOLCHAIN_PATH="${TOOLCHAIN_PATH:-/workspace/riscv64-unknown-linux_gnu_14.2.0}"
PYTORCH_INSTALL=""
BUILD_JOBS=$(nproc)
CLEAN_BUILD=0
BUILD_PYTORCH=0
PYTORCH_SOURCE_DIR=""
PYTORCH_BRANCH="v2.3.0"
PYTORCH_CLONE_URL="https://github.com/pytorch/pytorch.git"

# Versions
OPENSBI_VERSION="v1.7"
LINUX_VERSION="v6.10.5"
ALPINE_VERSION="3.21.0"
LINUX_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored message
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Parse command line arguments
show_help() {
    sed -n '/^#/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --toolchain)
            TOOLCHAIN_PATH="$2"
            shift 2
            ;;
        --pytorch)
            PYTORCH_INSTALL="$2"
            shift 2
            ;;
        --build-pytorch)
            BUILD_PYTORCH=1
            shift
            ;;
        --pytorch-source)
            PYTORCH_SOURCE_DIR="$2"
            shift 2
            ;;
        --pytorch-branch)
            PYTORCH_BRANCH="$2"
            shift 2
            ;;
        --pytorch-clone-url)
            PYTORCH_CLONE_URL="$2"
            shift 2
            ;;
        --jobs)
            BUILD_JOBS="$2"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=1
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate requirements
if [ $BUILD_PYTORCH -eq 1 ] && [ -z "$PYTORCH_INSTALL" ]; then
    PYTORCH_INSTALL="$PWD/artifacts/pytorch-install"
fi

if [ -z "$PYTORCH_INSTALL" ]; then
    log_error "PyTorch install directory not specified"
    echo "Use: $0 --pytorch /path/to/pytorch/install (or pass --build-pytorch)"
    exit 1
fi

if [ ! -d "$TOOLCHAIN_PATH" ]; then
    log_error "RISC-V toolchain not found at: $TOOLCHAIN_PATH"
    exit 1
fi

if [ $BUILD_PYTORCH -eq 1 ]; then
    log_info "Building PyTorch for riscv64 (install -> $PYTORCH_INSTALL)"
    BUILD_CMD=("$PWD/build_pytorch_riscv.sh" --toolchain "$TOOLCHAIN_PATH" --install "$PYTORCH_INSTALL" --jobs "$BUILD_JOBS")
    if [ -n "$PYTORCH_SOURCE_DIR" ]; then
        BUILD_CMD+=(--source "$PYTORCH_SOURCE_DIR")
    fi
    if [ -n "$PYTORCH_BRANCH" ]; then
        BUILD_CMD+=(--branch "$PYTORCH_BRANCH")
    fi
    if [ -n "$PYTORCH_CLONE_URL" ]; then
        BUILD_CMD+=(--clone-url "$PYTORCH_CLONE_URL")
    fi
    "${BUILD_CMD[@]}"
fi

if [ ! -d "$PYTORCH_INSTALL" ]; then
    log_error "PyTorch install directory not found at: $PYTORCH_INSTALL"
    exit 1
fi

# Check required tools
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command not found: $1"
        log_error "Please install it and try again"
        exit 1
    fi
}

log_info "Checking required tools..."
check_command make
check_command gcc
check_command wget
check_command cpio
check_command gzip
check_command tar
check_command git

# Set up environment
export CROSS_COMPILE="${TOOLCHAIN_PATH}/bin/riscv64-unknown-linux-gnu-"
export ARCH=riscv
export PATH="${TOOLCHAIN_PATH}/bin:$PATH"

# Project directories
PROJECT_ROOT="$(pwd)"
SRC_DIR="$PROJECT_ROOT/src"
BUILD_DIR="$PROJECT_ROOT/build"
ROOTFS_DIR="$PROJECT_ROOT/rootfs_alpine"

log_info "Build configuration:"
log_info "  Project root: $PROJECT_ROOT"
log_info "  Toolchain: $TOOLCHAIN_PATH"
log_info "  PyTorch: $PYTORCH_INSTALL"
log_info "  Build jobs: $BUILD_JOBS"
log_info "  Clean build: $CLEAN_BUILD"
log_info "  Build PyTorch: $BUILD_PYTORCH"

# Clean if requested
if [ $CLEAN_BUILD -eq 1 ]; then
    log_warn "Cleaning build directories..."
    rm -rf "$BUILD_DIR"
    rm -rf "$ROOTFS_DIR"
    rm -f initramfs_alpine.cpio.gz
fi

# Create directories
log_info "Creating directory structure..."
mkdir -p "$SRC_DIR"
mkdir -p "$BUILD_DIR"

# ============================================================================
# Step 1: Clone or update OpenSBI
# ============================================================================
log_info "=========================================="
log_info "Step 1: Preparing OpenSBI sources"
log_info "=========================================="

if [ ! -d "$SRC_DIR/opensbi" ]; then
    log_info "Cloning OpenSBI..."
    cd "$SRC_DIR"
    git clone https://github.com/riscv-software-src/opensbi.git
    cd opensbi
    git checkout "$OPENSBI_VERSION"
else
    log_info "OpenSBI already cloned, updating..."
    cd "$SRC_DIR/opensbi"
    git fetch
    git checkout "$OPENSBI_VERSION"
fi

# ============================================================================
# Step 2: Build OpenSBI
# ============================================================================
log_info "=========================================="
log_info "Step 2: Building OpenSBI firmware"
log_info "=========================================="

cd "$SRC_DIR/opensbi"
log_info "Building OpenSBI for generic platform..."
make PLATFORM=generic CROSS_COMPILE="$CROSS_COMPILE" O="$BUILD_DIR/opensbi" -j"$BUILD_JOBS"

FIRMWARE_PATH="$BUILD_DIR/opensbi/platform/generic/firmware/fw_jump.bin"
if [ -f "$FIRMWARE_PATH" ]; then
    FIRMWARE_SIZE=$(du -h "$FIRMWARE_PATH" | cut -f1)
    log_info "✓ OpenSBI firmware built successfully: $FIRMWARE_SIZE"
else
    log_error "OpenSBI firmware not found at: $FIRMWARE_PATH"
    exit 1
fi

# ============================================================================
# Step 3: Clone or update Linux kernel
# ============================================================================
log_info "=========================================="
log_info "Step 3: Preparing Linux kernel sources"
log_info "=========================================="

LINUX_SRC="$SRC_DIR/linux"
LINUX_GIT="$LINUX_SRC/.git"
NEED_KERNEL_CLONE=0
if [ ! -d "$LINUX_GIT" ]; then
    NEED_KERNEL_CLONE=1
else
    cd "$LINUX_SRC"
    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
        log_warn "Existing Linux tree has no commit; re-cloning"
        NEED_KERNEL_CLONE=1
    else
        CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
        if [ "$CURRENT_REMOTE" != "$LINUX_REPO" ]; then
            log_warn "Updating Linux kernel remote to $LINUX_REPO"
            git remote set-url origin "$LINUX_REPO"
        fi
        git fetch --depth 1 origin "$LINUX_VERSION"
        git checkout --force --detach FETCH_HEAD
        git clean -fdx
    fi
    cd "$PROJECT_ROOT"
fi

if [ $NEED_KERNEL_CLONE -eq 1 ]; then
    log_info "Cloning Linux kernel from $LINUX_REPO (ref $LINUX_VERSION)..."
    rm -rf "$LINUX_SRC"
    git clone --depth 1 --branch "$LINUX_VERSION" "$LINUX_REPO" "$LINUX_SRC"
else
    log_info "Linux kernel already cloned; ensuring $LINUX_VERSION is checked out"
fi

# ============================================================================
# Step 4: Configure Linux kernel
# ============================================================================
log_info "=========================================="
log_info "Step 4: Configuring Linux kernel"
log_info "=========================================="

cd "$SRC_DIR/linux"
log_info "Creating default RISC-V configuration..."
make ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" O="$BUILD_DIR/linux" defconfig

# Disable embedded initramfs (critical!)
log_info "Disabling embedded initramfs..."
cd "$BUILD_DIR/linux"
sed -i 's/CONFIG_INITRAMFS_SOURCE=.*/CONFIG_INITRAMFS_SOURCE=""/' .config

# ============================================================================
# Step 5: Build Linux kernel
# ============================================================================
log_info "=========================================="
log_info "Step 5: Building Linux kernel"
log_info "=========================================="

cd "$SRC_DIR/linux"
log_info "Building kernel (this may take several minutes)..."
make ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" O="$BUILD_DIR/linux" -j"$BUILD_JOBS"

KERNEL_PATH="$BUILD_DIR/linux/arch/riscv/boot/Image"
if [ -f "$KERNEL_PATH" ]; then
    KERNEL_SIZE=$(du -h "$KERNEL_PATH" | cut -f1)
    log_info "✓ Linux kernel built successfully: $KERNEL_SIZE"
else
    log_error "Kernel image not found at: $KERNEL_PATH"
    exit 1
fi

# ============================================================================
# Step 6: Download Alpine Linux rootfs
# ============================================================================
log_info "=========================================="
log_info "Step 6: Preparing Alpine Linux rootfs"
log_info "=========================================="

if [ ! -d "$ROOTFS_DIR" ] || [ ! -f "$ROOTFS_DIR/bin/busybox" ]; then
    log_info "Downloading Alpine Linux RISC-V rootfs..."
    mkdir -p "$ROOTFS_DIR"
    cd "$ROOTFS_DIR"

    ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/riscv64/alpine-minirootfs-${ALPINE_VERSION}-riscv64.tar.gz"
    wget -q --show-progress "$ALPINE_URL" -O alpine.tar.gz

    log_info "Extracting Alpine rootfs..."
    tar xzf alpine.tar.gz
    rm alpine.tar.gz

    log_info "✓ Alpine Linux rootfs ready"
else
    log_info "Alpine rootfs already exists"
fi

# ============================================================================
# Step 7: Copy PyTorch libraries
# ============================================================================
log_info "=========================================="
log_info "Step 7: Installing PyTorch libraries"
log_info "=========================================="

log_info "Creating library directories..."
mkdir -p "$ROOTFS_DIR/usr/local/lib"

log_info "Copying PyTorch libraries..."
if [ -d "$PYTORCH_INSTALL/lib" ]; then
    cp -v "$PYTORCH_INSTALL/lib"/*.so* "$ROOTFS_DIR/usr/local/lib/" 2>&1 | head -20
    log_info "✓ PyTorch libraries copied"
else
    log_error "PyTorch lib directory not found: $PYTORCH_INSTALL/lib"
    exit 1
fi

log_info "Copying system libraries from toolchain..."
TOOLCHAIN_SYSROOT="$TOOLCHAIN_PATH/sysroot/lib64/lp64d"
if [ -d "$TOOLCHAIN_SYSROOT" ]; then
    cp -r "$TOOLCHAIN_SYSROOT"/* "$ROOTFS_DIR/lib/" 2>&1 | head -10
    log_info "✓ System libraries copied"
else
    log_warn "Toolchain sysroot not found, PyTorch may need additional dependencies"
fi

# Apply rootfs overlay if present
OVERLAY_DIR="$PROJECT_ROOT/overlays/rootfs_alpine"
if [ -d "$OVERLAY_DIR" ]; then
    log_info "Applying rootfs overlay from $OVERLAY_DIR"
    (cd "$OVERLAY_DIR" && tar -cf - .) | (cd "$ROOTFS_DIR" && tar -xf -)
    log_info "✓ Rootfs overlay applied"
fi

# ============================================================================
# Step 8: Create init script
# ============================================================================
log_info "=========================================="
log_info "Step 8: Creating init script"
log_info "=========================================="

if [ ! -f "$ROOTFS_DIR/init" ]; then
    cat > "$ROOTFS_DIR/init" << 'EOF'
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
    log_info "✓ Default init script created"
else
    log_info "Init script provided by overlay"
fi

chmod +x "$ROOTFS_DIR/init"

# ============================================================================
# Step 9: Create initramfs
# ============================================================================
log_info "=========================================="
log_info "Step 9: Creating initramfs"
log_info "=========================================="

cd "$ROOTFS_DIR"
log_info "Packing rootfs into initramfs (this may take a minute)..."
find . -print0 | cpio --null --create --format=newc 2>/dev/null | gzip -9 > "$PROJECT_ROOT/initramfs_alpine.cpio.gz"

INITRAMFS_PATH="$PROJECT_ROOT/initramfs_alpine.cpio.gz"
if [ -f "$INITRAMFS_PATH" ]; then
    INITRAMFS_SIZE=$(du -h "$INITRAMFS_PATH" | cut -f1)
    log_info "✓ Initramfs created: $INITRAMFS_SIZE"
else
    log_error "Failed to create initramfs"
    exit 1
fi

# ============================================================================
# Step 10: Create QEMU launch script
# ============================================================================
log_info "=========================================="
log_info "Step 10: Creating QEMU launch script"
log_info "=========================================="

cd "$PROJECT_ROOT"
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
log_info "✓ QEMU launch script created"

# ============================================================================
# Build Summary
# ============================================================================
log_info ""
log_info "=========================================="
log_info "Build completed successfully!"
log_info "=========================================="
log_info ""
log_info "Generated files:"
log_info "  Firmware:  $FIRMWARE_PATH ($FIRMWARE_SIZE)"
log_info "  Kernel:    $KERNEL_PATH ($KERNEL_SIZE)"
log_info "  Initramfs: $INITRAMFS_PATH ($INITRAMFS_SIZE)"
log_info "  Launcher:  $PROJECT_ROOT/run_qemu.sh"
log_info ""
log_info "To run the system:"
log_info "  cd $PROJECT_ROOT"
log_info "  ./run_qemu.sh"
log_info ""
log_info "Configuration options:"
log_info "  MEMORY=4G ./run_qemu.sh    # Set memory size"
log_info "  SMP=8 ./run_qemu.sh        # Set CPU count"
log_info ""
log_info "To exit QEMU: Press Ctrl-A then X"
log_info ""
