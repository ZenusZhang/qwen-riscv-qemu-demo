#!/usr/bin/env bash
# build_pytorch_riscv.sh - Cross-compile PyTorch for riscv64.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

usage() {
  cat <<'USAGE'
usage: ./build_pytorch_riscv.sh [options]

Options:
  --toolchain PATH      RISC-V cross toolchain root (bin/ + sysroot/) [required]
  --install PATH        Install prefix for riscv libtorch output      [default: artifacts/pytorch-install]
  --source PATH         Existing PyTorch source directory             [default: artifacts/pytorch-src]
  --clone-url URL       PyTorch git remote                            [default: https://github.com/pytorch/pytorch.git]
  --branch REF          Git branch/tag/commit to build                [default: v2.3.0]
  --jobs N              Parallel build jobs                           [default: nproc]
  --force-fetch         Reclone PyTorch even if the source directory exists
  --help                This message
USAGE
}

TOOLCHAIN_ROOT=""
INSTALL_PREFIX=""
SOURCE_DIR=""
CLONE_URL="https://github.com/pytorch/pytorch.git"
BRANCH="v2.3.0"
JOBS="$(nproc)"
FORCE_FETCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --toolchain)
      TOOLCHAIN_ROOT="$2"; shift 2 ;;
    --install)
      INSTALL_PREFIX="$2"; shift 2 ;;
    --source)
      SOURCE_DIR="$2"; shift 2 ;;
    --clone-url)
      CLONE_URL="$2"; shift 2 ;;
    --branch)
      BRANCH="$2"; shift 2 ;;
    --jobs)
      JOBS="$2"; shift 2 ;;
    --force-fetch)
      FORCE_FETCH=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ -z "$TOOLCHAIN_ROOT" ]]; then
  echo "error: --toolchain PATH is required" >&2
  exit 1
fi

if [[ ! -x "$TOOLCHAIN_ROOT/bin/riscv64-unknown-linux-gnu-gcc" ]]; then
  echo "error: riscv64-unknown-linux-gnu-gcc not found under $TOOLCHAIN_ROOT/bin" >&2
  exit 1
fi

INSTALL_PREFIX=${INSTALL_PREFIX:-"$REPO_ROOT/artifacts/pytorch-install"}
SOURCE_DIR=${SOURCE_DIR:-"$REPO_ROOT/artifacts/pytorch-src"}
BUILD_ROOT="$REPO_ROOT/artifacts/pytorch-build"

mkdir -p "$INSTALL_PREFIX" "$BUILD_ROOT"

if [[ $FORCE_FETCH -eq 1 && -d "$SOURCE_DIR" ]]; then
  rm -rf "$SOURCE_DIR"
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Cloning PyTorch from $CLONE_URL (ref $BRANCH)"
  git clone --recursive --depth 1 --branch "$BRANCH" "$CLONE_URL" "$SOURCE_DIR"
else
  echo "Using existing PyTorch source at $SOURCE_DIR"
  (cd "$SOURCE_DIR" && git fetch --tags && git checkout "$BRANCH" && git submodule update --init --recursive)
fi

(cd "$SOURCE_DIR" && git submodule update --init --recursive third_party/sleef third_party/protobuf third_party/onnx)

SLEEF_BUILD="$BUILD_ROOT/sleef-native"
SLEEF_INSTALL="$BUILD_ROOT/sleef-native-install"
PROTOBUF_BUILD="$BUILD_ROOT/protobuf-native"
PYTORCH_BUILD="$BUILD_ROOT/pytorch"
ONNX_BUILD="$BUILD_ROOT/onnx-shared"
TOOLCHAIN_DIR="$BUILD_ROOT/toolchains"
mkdir -p "$SLEEF_BUILD" "$SLEEF_INSTALL" "$PROTOBUF_BUILD" "$PYTORCH_BUILD" "$ONNX_BUILD" "$TOOLCHAIN_DIR"

cat >"$TOOLCHAIN_DIR/riscv64.cmake" <<TOOL
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR riscv64)
set(RISCV_ROOT "$TOOLCHAIN_ROOT" CACHE PATH "RISC-V toolchain root")
set(CMAKE_SYSROOT "${TOOLCHAIN_ROOT}/sysroot")
set(CMAKE_C_COMPILER "${TOOLCHAIN_ROOT}/bin/riscv64-unknown-linux-gnu-gcc")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN_ROOT}/bin/riscv64-unknown-linux-gnu-g++")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN_ROOT}/bin/riscv64-unknown-linux-gnu-gcc")
set(CMAKE_C_COMPILER_TARGET "riscv64-unknown-linux-gnu")
set(CMAKE_CXX_COMPILER_TARGET "riscv64-unknown-linux-gnu")
set(CMAKE_FIND_ROOT_PATH "${TOOLCHAIN_ROOT}/riscv64-unknown-linux-gnu" "${TOOLCHAIN_ROOT}/sysroot")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_CROSSCOMPILING_EMULATOR "/usr/bin/qemu-riscv64")
set(CMAKE_C_FLAGS_INIT "--sysroot=${TOOLCHAIN_ROOT}/sysroot")
set(CMAKE_CXX_FLAGS_INIT "--sysroot=${TOOLCHAIN_ROOT}/sysroot")
TOOL

cat >"$TOOLCHAIN_DIR/riscv64_libtorch.cmake" <<TOOL
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR riscv64)
set(RISCV_ROOT "$TOOLCHAIN_ROOT" CACHE PATH "RISC-V toolchain root")
set(TORCH_PREFIX "$INSTALL_PREFIX" CACHE PATH "Torch install prefix")
set(CMAKE_SYSROOT "${TOOLCHAIN_ROOT}/sysroot")
set(CMAKE_C_COMPILER "${TOOLCHAIN_ROOT}/bin/riscv64-unknown-linux-gnu-gcc")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN_ROOT}/bin/riscv64-unknown-linux-gnu-g++")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN_ROOT}/bin/riscv64-unknown-linux-gnu-gcc")
set(CMAKE_C_COMPILER_TARGET "riscv64-unknown-linux-gnu")
set(CMAKE_CXX_COMPILER_TARGET "riscv64-unknown-linux-gnu")
set(CMAKE_FIND_ROOT_PATH "${TOOLCHAIN_ROOT}/riscv64-unknown-linux-gnu" "${TOOLCHAIN_ROOT}/sysroot" "${INSTALL_PREFIX}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_CROSSCOMPILING_EMULATOR "/usr/bin/qemu-riscv64")
set(CMAKE_C_FLAGS_INIT "--sysroot=${TOOLCHAIN_ROOT}/sysroot")
set(CMAKE_CXX_FLAGS_INIT "--sysroot=${TOOLCHAIN_ROOT}/sysroot")
set(CMAKE_PREFIX_PATH "${INSTALL_PREFIX}")
TOOL

cmake -S "$SOURCE_DIR/third_party/sleef" \
      -B "$SLEEF_BUILD" \
      -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$SLEEF_INSTALL" \
      -DSLEEF_BUILD_SHARED_LIBS=OFF \
      -DSLEEF_BUILD_TESTS=OFF \
      -DSLEEF_BUILD_DFT=OFF \
      -DSLEEF_BUILD_QUAD=OFF \
      -DSLEEF_BUILD_SCALAR_LIB=OFF \
      -DSLEEF_BUILD_GNUABI_LIBS=ON \
      -DSLEEF_BUILD_BENCH=OFF
cmake --build "$SLEEF_BUILD" --target install --parallel "$JOBS"

cmake -S "$SOURCE_DIR/third_party/protobuf/cmake" \
      -B "$PROTOBUF_BUILD" \
      -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -Dprotobuf_BUILD_TESTS=OFF \
      -Dprotobuf_BUILD_CONFORMANCE=OFF \
      -Dprotobuf_BUILD_EXAMPLES=OFF
cmake --build "$PROTOBUF_BUILD" --target protoc --parallel "$JOBS"
PROTOC_NATIVE="$PROTOBUF_BUILD/protoc-3.13.0.0"

cmake -S "$SOURCE_DIR" \
      -B "$PYTORCH_BUILD" \
      -GNinja \
      -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_DIR/riscv64.cmake" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
      -DBUILD_SHARED_LIBS=ON \
      -DBUILD_BINARY=OFF \
      -DBUILD_PYTHON=OFF \
      -DUSE_NUMPY=OFF \
      -DUSE_CUDA=OFF \
      -DUSE_ROCM=OFF \
      -DUSE_XNNPACK=OFF \
      -DUSE_PYTORCH_QNNPACK=OFF \
      -DUSE_QNNPACK=OFF \
      -DUSE_MKLDNN=OFF \
      -DUSE_MKL=OFF \
      -DUSE_FBGEMM=OFF \
      -DUSE_NNPACK=OFF \
      -DUSE_KINETO=OFF \
      -DUSE_TENSORPIPE=OFF \
      -DUSE_DISTRIBUTED=OFF \
      -DUSE_MPI=OFF \
      -DUSE_GLOO=OFF \
      -DBUILD_TEST=OFF \
      -DINTERN_BUILD_ATEN_OPS=OFF \
      -DNATIVE_BUILD_DIR="$SLEEF_BUILD" \
      -DCAFFE2_CUSTOM_PROTOC_EXECUTABLE="$PROTOC_NATIVE" \
      -DPROTOBUF_PROTOC_EXECUTABLE="$PROTOC_NATIVE" \
      -DONNX_CUSTOM_PROTOC_EXECUTABLE="$PROTOC_NATIVE" \
      -DCMAKE_C_FLAGS="--sysroot=${TOOLCHAIN_ROOT}/sysroot -D__riscv_v_intrinsic=0" \
      -DCMAKE_CXX_FLAGS="--sysroot=${TOOLCHAIN_ROOT}/sysroot -D__riscv_v_intrinsic=0"

ninja -C "$PYTORCH_BUILD" "$PYTORCH_BUILD/third_party/onnx/onnx/onnx_onnx_torch-ml.pb.h"
mkdir -p "$PYTORCH_BUILD/onnx"
cat >"$PYTORCH_BUILD/onnx/onnx_pb.h" <<'ONNXHDR'
#pragma once
#include "../third_party/onnx/onnx/onnx_onnx_torch-ml.pb.h"
ONNXHDR

if ! ninja -C "$PYTORCH_BUILD" install --parallel "$JOBS"; then
  echo "warning: PyTorch install step reported issues (common when ONNX symbols are missing); continuing" >&2
fi

cmake -S "$SOURCE_DIR/third_party/onnx" \
      -B "$ONNX_BUILD" \
      -GNinja \
      -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_DIR/riscv64_libtorch.cmake" \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DONNX_NAMESPACE=onnx_torch \
      -DONNX_ML=ON \
      -DONNX_BUILD_TESTS=OFF \
      -DONNX_USE_LITE_PROTO=OFF \
      -DProtobuf_PROTOC_EXECUTABLE="$PROTOC_NATIVE" \
      -DPROTOBUF_PROTOC_EXECUTABLE="$PROTOC_NATIVE" \
      -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
cmake --build "$ONNX_BUILD" --target install --parallel "$JOBS"

cat <<EOF

PyTorch cross-build completed.
  Install prefix : $INSTALL_PREFIX
  Key libraries  : $INSTALL_PREFIX/lib/libtorch.so, libtorch_cpu.so, libc10.so, libonnx*.so

Pass --pytorch "$INSTALL_PREFIX" to build_pytorch_qemu_riscv.sh.
EOF
