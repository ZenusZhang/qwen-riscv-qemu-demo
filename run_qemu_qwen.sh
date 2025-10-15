#!/usr/bin/env bash
set -euo pipefail

ROOT=$(realpath "$(dirname "$0")")
BIOS="$ROOT/build/opensbi/platform/generic/firmware/fw_jump.bin"
KERNEL="$ROOT/build/linux/arch/riscv/boot/Image"
INITRAMFS="$ROOT/initramfs_alpine_small.cpio.gz"
MODEL_DIR="${MODEL_DIR:-$ROOT/models}"
MODEL_ARCHIVE="${MODEL_ARCHIVE:-$MODEL_DIR/qwen3_0_6b.ts.gz}"
MODEL_TS="${MODEL_TS:-$MODEL_DIR/qwen3_0_6b.ts}"
MEM=${MEMORY:-4G}
SMP=${SMP:-32}
CPU_OPTS="${CPU:-rv64,v=true,vlen=128,elen=64}"

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

prepare_model() {
  if [ -f "$MODEL_TS" ]; then
    return
  fi

  if [ ! -f "$MODEL_ARCHIVE" ]; then
    cat >&2 <<MSG
Qwen3 0.6B archive not found at $MODEL_ARCHIVE
Place qwen3_0_6b.ts.gz inside $MODEL_DIR or override MODEL_ARCHIVE/MODEL_TS.
MSG
    exit 1
  fi

  echo "Preparing host-side TorchScript model at $MODEL_TS (this may take a minute)..."
  tmp="$MODEL_TS.tmp"
  if ! gzip -dc "$MODEL_ARCHIVE" > "$tmp"; then
    rm -f "$tmp"
    echo "Failed to decompress $MODEL_ARCHIVE" >&2
    exit 1
  fi
  mv "$tmp" "$MODEL_TS"
}

prepare_model

echo "Starting QEMU RISC-V system for Qwen3 0.6B demo..."
echo "  Firmware: $BIOS"
echo "  Kernel:   $KERNEL"
echo "  Initramfs: $INITRAMFS"
echo "  CPU: $CPU_OPTS"
echo "  Model dir shared via 9p: $MODEL_DIR"
echo "  TorchScript: $MODEL_TS"
echo "  Memory: $MEM"
echo "  CPUs: $SMP"
echo ""
echo "Login shell auto-mounts /mnt/host and runs the demo with MAX_NEW_TOKENS=1." 
echo "To rerun manually inside QEMU:"
echo "  QWEN_MODEL_PATH=/mnt/host/$(basename "$MODEL_TS") \\
    MODEL_ARCHIVE=/mnt/host/$(basename "$MODEL_TS") /usr/local/bin/run_qwen_demo.sh"
echo ""
echo "To exit QEMU, press Ctrl-A then X"
echo ""

exec qemu-system-riscv64 \
  -machine virt \
  -cpu "$CPU_OPTS" \
  -m "$MEM" \
  -smp "$SMP" \
  -nographic \
  -bios "$BIOS" \
  -kernel "$KERNEL" \
  -initrd "$INITRAMFS" \
  -append "console=ttyS0 earlycon=sbi root=/dev/ram0 rw" \
  -virtfs local,path="$MODEL_DIR",mount_tag=hostshare,security_model=none,id=hostshare
