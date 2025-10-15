# Models Directory

Place the Qwen3-0.6B TorchScript artifacts here before launching QEMU.

Required files:

- `qwen3_0_6b.ts.gz` – compressed TorchScript archive (will be decompressed automatically)
- `qwen3_0_6b.ts` – optional; if present the launch script skips decompression

These files are shared with the guest at `/mnt/host/` via the `run_qemu_qwen.sh` launcher.
