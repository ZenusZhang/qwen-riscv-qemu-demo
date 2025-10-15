#!/usr/bin/env bash
set -euo pipefail

ROOT=$(realpath "$(dirname "$0")")
MODEL_DIR="$ROOT/models"
MODEL_ARCHIVE="$MODEL_DIR/qwen3_0_6b.ts.gz"
MODEL_TS="$MODEL_DIR/qwen3_0_6b.ts"
PROMPT="$ROOT/rootfs_alpine/usr/local/share/qwen/prompt_tokens.txt"
OUTPUT="$ROOT/models/repro_output_tokens.txt"
INFER_BIN="$ROOT/../libtorch_test/build/qwen3_infer"

if [ ! -f "$MODEL_ARCHIVE" ]; then
  echo "Missing model archive at $MODEL_ARCHIVE" >&2
  exit 1
fi

if [ ! -x "$INFER_BIN" ]; then
  echo "Missing qwen3_infer binary at $INFER_BIN" >&2
  exit 1
fi

cleanup() {
  rm -f "$MODEL_TS" "$OUTPUT"
}
trap cleanup EXIT

echo "Decompressing TorchScript model..."
gzip -dc "$MODEL_ARCHIVE" > "$MODEL_TS"

set +e
"$INFER_BIN" "$MODEL_TS" "$PROMPT" "$OUTPUT" 4 151645
status=$?
set -e

echo "qwen3_infer exited with status $status"
exit $status
