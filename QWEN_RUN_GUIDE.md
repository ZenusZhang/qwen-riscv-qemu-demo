# Qwen3-0.6B Demo on RISC-V QEMU

This guide explains how to package, boot, and run the PyTorch Qwen3-0.6B TorchScript demo on a RISC-V QEMU full-system guest. Everything below assumes you are working inside the `pytorch/riscv_qemu_demo` directory that already contains the prepared root filesystem and model assets.

## 1. Requirements

- RISC-V toolchain and QEMU system emulator installed on the host (`qemu-system-riscv64` in `$PATH`).
- Host filesystem writable so the demo script can unpack the TorchScript model.
- The prebuilt artifacts checked in under `riscv_qemu_demo/` (firmware, kernel, initramfs, rootfs, PyTorch libs, TorchScript model).

Optional but recommended: at least 8 GB of RAM and 4+ cores on the host to keep QEMU responsive.

## 2. Build or Verify System Artifacts

The launch script expects the following images:

- `build/opensbi/platform/generic/firmware/fw_jump.bin`
- `build/linux/arch/riscv/boot/Image`
- `initramfs_alpine_small.cpio.gz`

If they already exist, skip this step. Otherwise generate them either with the automated scripts or the manual instructions that live in this repo.

### 2.1 Build libtorch for riscv64 (optional)

If you do not already have a riscv64 libtorch install, run:

```bash
./build_pytorch_riscv.sh --toolchain /path/to/riscv/toolchain \
    --install artifacts/pytorch-install
```

Use `--force-fetch` to reclone PyTorch or `--branch`/`--clone-url` to control the checkout. The resulting install prefix is what you pass via `--pytorch` to the system builder below.

### 2.2 Automated system build (recommended)

```bash
cd pytorch/riscv_qemu_demo
./build_pytorch_qemu_riscv.sh --build-pytorch --toolchain /path/to/toolchain \
    --pytorch /absolute/path/to/libtorch/install
```

Drop `--build-pytorch` if you are supplying a prebuilt libtorch directory. The script clones OpenSBI and the Linux kernel, builds them for RISC-V, downloads Alpine, stages the PyTorch libraries, and produces the initramfs. After it completes, verify the outputs:

```bash
ls -lh build/opensbi/platform/generic/firmware/fw_jump.bin
ls -lh build/linux/arch/riscv/boot/Image
ls -lh initramfs_alpine_small.cpio.gz
```

### 2.3 Manual assembly

If you need to rebuild components by hand, follow `BUILD_INSTRUCTIONS.md` within this directory. The key points are:

1. Build OpenSBI with the cross toolchain (`make PLATFORM=generic O=build/opensbi`).
2. Configure and build the Linux kernel for `riscv64` (`make ARCH=riscv O=build/linux defconfig && make ...`).
3. Prepare the Alpine rootfs, copy the PyTorch shared libraries and `qwen3_infer` binary, then pack it into `initramfs_alpine_small.cpio.gz`.

## 3. Prepare the TorchScript Model

The repository ships with `models/qwen3_0_6b.ts.gz`. The launch script will automatically create the decompressed TorchScript file (`models/qwen3_0_6b.ts`) the first time you run it. You can do this manually if you prefer:

```bash
cd pytorch/riscv_qemu_demo
gzip -dc models/qwen3_0_6b.ts.gz > models/qwen3_0_6b.ts
```

Both files are shared with the guest via 9p.

## 4. Launch the QEMU Demo

From the demo directory run:

```bash
cd pytorch/riscv_qemu_demo
./run_qemu_qwen.sh
```

Environment variables you can override:

- `MEMORY=8G` – adjust guest RAM (default 4 GB)
- `SMP=8` – set the virtual CPU count (default 4, script upgrades to 32 when available)
- `CPU='rv64,v=true,vlen=128,elen=64'` – CPU string passed to QEMU

During start-up the script reports the firmware, kernel, initramfs, and TorchScript path it will use. It also mounts `riscv_qemu_demo/models/` into the guest under `/mnt/host` using 9p.

## 5. In-Guest Workflow

The guest boots into BusyBox `sh`. The init script automatically

1. Mounts `/mnt/host` (`hostshare` 9p export).
2. Checks for `/mnt/host/qwen3_0_6b.ts`.
3. Runs the inference demo with `MAX_NEW_TOKENS=1`:
   ```
   QWEN_MODEL_PATH=/mnt/host/qwen3_0_6b.ts \
   MODEL_ARCHIVE=/mnt/host/qwen3_0_6b.ts \
   /usr/local/bin/run_qwen_demo.sh
   ```
4. Prints the command above so you can rerun it manually if desired.

The prompt and output live in these guest paths:

- `/usr/local/share/qwen/prompt_tokens.txt` – token IDs used as the initial prompt (defaults to `9707 504 431 27629 19625`).
- `/tmp/qwen_output_tokens.txt` – tokens generated during the run.

## 6. Customisation and Reruns

- Generate more tokens:

  ```bash
  MAX_NEW_TOKENS=4 \
  QWEN_MODEL_PATH=/mnt/host/qwen3_0_6b.ts \
  MODEL_ARCHIVE=/mnt/host/qwen3_0_6b.ts \
  /usr/local/bin/run_qwen_demo.sh
  ```

- Swap prompts: edit `/usr/local/share/qwen/prompt_tokens.txt` on the host before launching or inside the guest after booting.

- Change the model location: place a different TorchScript file under `models/` and set the `MODEL_ARCHIVE`/`MODEL_TS` env vars before calling `run_qemu_qwen.sh`.

## 7. Shutdown and Cleanup

- Leave QEMU with `Ctrl-A` then `X` from the host terminal.
- The guest stores the decompressed model under `/mnt/host` (host filesystem), so subsequent boots skip the slow gzip step.
- Delete the model cache if you want to reclaim space:

  ```bash
  rm -f models/qwen3_0_6b.ts
  ```

## 8. Troubleshooting

- **Missing firmware/kernel/initramfs** – rerun the build script or follow the manual steps in `BUILD_INSTRUCTIONS.md`.
- **Mount failures** – ensure `mount -t 9p -o trans=virtio,version=9p2000.L hostshare /mnt/host` succeeds inside the guest; the launch script exports `models/` by default.
- **Illegal instruction** – the demo requires RVV support. Confirm QEMU accepts the `-cpu rv64,v=true,...` flag and the guest prints `Boot HART Base ISA: rv64imafdcvh` during boot.
- **Slow inference** – the QEMU guest is fully emulated; stick to `MAX_NEW_TOKENS=1` or give QEMU more host cores (`SMP=`) to keep latency reasonable.

Following these steps on any machine with the prerequisites in place will reproduce the PyTorch Qwen3-0.6B inference demo inside the RISC-V QEMU environment.
