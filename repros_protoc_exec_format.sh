#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOC="$REPO_ROOT/artifacts/pytorch-build/protobuf-native/protoc-3.13.0.0"

if [[ ! -x "$PROTOC" ]]; then
  echo "error: protoc binary not found at $PROTOC" >&2
  exit 1
fi

echo "running protoc --version to verify host executable"
"$PROTOC" --version
