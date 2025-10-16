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
  # (cd "$SOURCE_DIR" && git fetch --tags && git checkout "$BRANCH" && git submodule update --init --recursive)
fi

(cd "$SOURCE_DIR" && git submodule update --init --recursive third_party/sleef third_party/protobuf third_party/onnx)

SLEEF_BUILD="$BUILD_ROOT/sleef-native"
SLEEF_INSTALL="$BUILD_ROOT/sleef-native-install"
PROTOBUF_BUILD="$BUILD_ROOT/protobuf-native"
PROTOC_LEGACY="$PROTOBUF_BUILD/protoc-3.13.0.0"
PYTORCH_BUILD="$BUILD_ROOT/pytorch"
ONNX_BUILD="$BUILD_ROOT/onnx-shared"
TOOLCHAIN_DIR="$BUILD_ROOT/toolchains"
mkdir -p "$SLEEF_BUILD" "$SLEEF_INSTALL" "$PROTOBUF_BUILD" "$PYTORCH_BUILD" "$ONNX_BUILD" "$TOOLCHAIN_DIR"

HOST_CC="$(command -v gcc)"
HOST_CXX="$(command -v g++)"

if [[ -z "$HOST_CC" || -z "$HOST_CXX" ]]; then
  echo "error: host gcc/g++ not found in PATH" >&2
  exit 1
fi

if [[ -x "$PROTOC_LEGACY" ]]; then
  if "$PROTOC_LEGACY" --version >/dev/null 2>&1; then
    log_info "Reusing existing host protoc binary at $PROTOC_LEGACY"
  else
    log_warn "Stale non-host protoc detected at $PROTOC_LEGACY; rebuilding"
    rm -rf "$PROTOBUF_BUILD"
    mkdir -p "$PROTOBUF_BUILD"
  fi
fi

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
      -DCMAKE_C_COMPILER="$(command -v gcc)" \
      -DCMAKE_CXX_COMPILER="$(command -v g++)" \
      -DCMAKE_INSTALL_PREFIX="$SLEEF_INSTALL" \
      -DSLEEF_BUILD_SHARED_LIBS=OFF \
      -DSLEEF_BUILD_TESTS=OFF \
      -DSLEEF_BUILD_DFT=OFF \
      -DSLEEF_BUILD_QUAD=OFF \
      -DSLEEF_BUILD_SCALAR_LIB=OFF \
      -DSLEEF_BUILD_GNUABI_LIBS=ON \
      -DSLEEF_BUILD_GNUABI=OFF \
      -DENABLE_PURECFMA_SCALAR=OFF \
      -DSLEEF_BUILD_BENCH=OFF
cmake --build "$SLEEF_BUILD" --target install --parallel "$JOBS"

cmake -S "$SOURCE_DIR/third_party/protobuf/cmake" \
      -B "$PROTOBUF_BUILD" \
      -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER="$HOST_CC" \
      -DCMAKE_CXX_COMPILER="$HOST_CXX" \
      -Dprotobuf_BUILD_TESTS=OFF \
      -Dprotobuf_BUILD_CONFORMANCE=OFF \
      -Dprotobuf_BUILD_EXAMPLES=OFF
cmake --build "$PROTOBUF_BUILD" --target protoc --parallel "$JOBS"

if ! "$PROTOC_LEGACY" --version >/dev/null 2>&1; then
  log_error "Failed to build a runnable host protoc at $PROTOC_LEGACY"
  exit 1
fi

ONNX_SCHEMA_HEADER="$SOURCE_DIR/third_party/onnx/onnx/defs/schema.h"
if [[ -f "$ONNX_SCHEMA_HEADER" ]] && ! grep -q 'onnx_pb.h' "$ONNX_SCHEMA_HEADER"; then
  echo "Ensuring onnx schema.h includes onnx_pb.h"
  env ONNX_SCHEMA_HEADER="$ONNX_SCHEMA_HEADER" python3 - <<'PY_SCHEMA'
import os
from pathlib import Path
header = Path(os.environ['ONNX_SCHEMA_HEADER'])
text = header.read_text()
needle = '#include "onnx/defs/shape_inference.h"

'
if needle in text:
    replacement = '#include "onnx/defs/shape_inference.h"
#include "onnx/onnx_pb.h"

'
    text = text.replace(needle, replacement, 1)
    header.write_text(text)
PY_SCHEMA
fi

CPUINFO_API_C="$SOURCE_DIR/third_party/cpuinfo/src/api.c"
if [[ -f "$CPUINFO_API_C" ]] && ! grep -q "#define _GNU_SOURCE" "$CPUINFO_API_C"; then
  echo "Patching cpuinfo api.c to define _GNU_SOURCE for syscall()"
  env CPUINFO_API_C="$CPUINFO_API_C" python3 - <<'PY_CPUINFO'
import os
from pathlib import Path
api_path = Path(os.environ['CPUINFO_API_C'])
text = api_path.read_text()
lines = text.splitlines()
if '#define _GNU_SOURCE' not in lines[:5]:
    api_path.write_text('#define _GNU_SOURCE\n' + text)
PY_CPUINFO
fi

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
      -DCAFFE2_CUSTOM_PROTOC_EXECUTABLE="$PROTOC_LEGACY" \
      -DPROTOBUF_PROTOC_EXECUTABLE="$PROTOC_LEGACY" \
      -DONNX_CUSTOM_PROTOC_EXECUTABLE="$PROTOC_LEGACY" \
      -DCMAKE_C_FLAGS="--sysroot=${TOOLCHAIN_ROOT}/sysroot -D__riscv_v_intrinsic=0" \
      -DCMAKE_CXX_FLAGS="--sysroot=${TOOLCHAIN_ROOT}/sysroot -D__riscv_v_intrinsic=0"

ninja -C "$PYTORCH_BUILD" "$PYTORCH_BUILD/third_party/onnx/onnx/onnx_onnx_torch-ml.pb.h"
mkdir -p "$PYTORCH_BUILD/onnx"
cat >"$PYTORCH_BUILD/onnx/onnx_pb.h" <<'ONNXHDR'
#pragma once
#include "../third_party/onnx/onnx/onnx_onnx_torch-ml.pb.h"
ONNXHDR

echo "Installing PyTorch (ninja install)"
ninja -C "$PYTORCH_BUILD" install --parallel "$JOBS"

TORCH_LIB_DIR="$INSTALL_PREFIX/lib"
if [[ ! -f "$TORCH_LIB_DIR/libtorch.so" || ! -f "$TORCH_LIB_DIR/libtorch_cpu.so" ]]; then
  echo "error: libtorch shared libraries missing from $TORCH_LIB_DIR after install" >&2
  exit 1
fi

PROTOBUF_ONNX_VERSION="22.3"
PROTOBUF_ONNX_ZIP="$BUILD_ROOT/protoc-${PROTOBUF_ONNX_VERSION}-linux-x86_64.zip"
PROTOBUF_ONNX_DIR="$BUILD_ROOT/protoc-${PROTOBUF_ONNX_VERSION}-host"
PROTOC_ONNX_BIN="$PROTOBUF_ONNX_DIR/bin/protoc"
PROTOC_ONNX_WRAPPER="$PROTOBUF_ONNX_DIR/protoc.sh"

if [[ ! -x "$PROTOC_ONNX_WRAPPER" ]]; then
  echo "Fetching host protoc ${PROTOBUF_ONNX_VERSION}"
  if [[ ! -f "$PROTOBUF_ONNX_ZIP" ]]; then
    curl -fL "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_ONNX_VERSION}/protoc-${PROTOBUF_ONNX_VERSION}-linux-x86_64.zip" -o "$PROTOBUF_ONNX_ZIP"
  fi
  rm -rf "$PROTOBUF_ONNX_DIR"
  mkdir -p "$PROTOBUF_ONNX_DIR"
  env PROTOBUF_ONNX_ZIP="$PROTOBUF_ONNX_ZIP" PROTOBUF_ONNX_DIR="$PROTOBUF_ONNX_DIR" python3 - <<'PY_UNZIP'
import os
import zipfile

zip_path = os.environ['PROTOBUF_ONNX_ZIP']
out_dir = os.environ['PROTOBUF_ONNX_DIR']
with zipfile.ZipFile(zip_path) as zf:
    zf.extractall(out_dir)
PY_UNZIP
  chmod +x "$PROTOC_ONNX_BIN"
  cat >"$PROTOC_ONNX_WRAPPER" <<'PROTOC_WRAPPER'
#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="${ROOT_DIR}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "${ROOT_DIR}/bin/protoc" "$@"
PROTOC_WRAPPER
  chmod +x "$PROTOC_ONNX_WRAPPER"
fi
if [[ ! -x "$PROTOC_ONNX_BIN" ]]; then
  chmod +x "$PROTOC_ONNX_BIN"
fi

PROTOC_ONNX="$PROTOC_ONNX_WRAPPER"



ONNX_CMAKE_FILE="$SOURCE_DIR/third_party/onnx/CMakeLists.txt"
if [[ -f "$ONNX_CMAKE_FILE" ]]; then
  env ONNX_CMAKE_FILE="$ONNX_CMAKE_FILE" python3 - <<'PY_ONNX'
import os
from pathlib import Path

cmake = Path(os.environ['ONNX_CMAKE_FILE'])
content = cmake.read_text()
needle = '    set(ONNX_PROTOC_EXECUTABLE $<TARGET_FILE:protobuf::protoc>)\n    set(Protobuf_VERSION "4.22.3")\n'
if needle not in content:
    raise SystemExit(0)
replacement = (
    '    set(ONNX_PROTOC_EXECUTABLE $<TARGET_FILE:protobuf::protoc>)\n'
    '    if(ONNX_CUSTOM_PROTOC_EXECUTABLE AND EXISTS "${ONNX_CUSTOM_PROTOC_EXECUTABLE}")\n'
    '      message(STATUS "Overriding protoc with ${ONNX_CUSTOM_PROTOC_EXECUTABLE}")\n'
    '      set(ONNX_PROTOC_EXECUTABLE "${ONNX_CUSTOM_PROTOC_EXECUTABLE}")\n'
    '    endif()\n'
    '    set(Protobuf_VERSION "4.22.3")\n'
)
if replacement.strip() in content:
    raise SystemExit(0)
content = content.replace(needle, replacement, 1)
cmake.write_text(content)
PY_ONNX
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
      -DProtobuf_PROTOC_EXECUTABLE="$PROTOC_ONNX" \
      -DPROTOBUF_PROTOC_EXECUTABLE="$PROTOC_ONNX" \
      -DONNX_CUSTOM_PROTOC_EXECUTABLE="$PROTOC_ONNX" \
      -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
PROTOBUF_PORT_HEADER="$ONNX_BUILD/_deps/protobuf-src/src/google/protobuf/port.h"
if [[ -f "$PROTOBUF_PORT_HEADER" ]] && ! grep -q '<cstdint>' "$PROTOBUF_PORT_HEADER"; then
  echo "Patching protobuf port.h to add <cstdint> include"
  env PROTOBUF_PORT_HEADER="$PROTOBUF_PORT_HEADER" python3 - <<'PY_PORT'
import os
from pathlib import Path
header = Path(os.environ['PROTOBUF_PORT_HEADER'])
text = header.read_text()
needle = "#include <type_traits>\n"
insert = "#include <type_traits>\n#include <cstdint>\n"
if insert in text:
    raise SystemExit(0)
if needle not in text:
    raise SystemExit('Failed to locate <type_traits> include in port.h')
header.write_text(text.replace(needle, insert, 1))
PY_PORT
fi

cmake --build "$ONNX_BUILD" --target install --parallel "$JOBS"

cat <<EOF

PyTorch cross-build completed.
  Install prefix : $INSTALL_PREFIX
  Key libraries  : $INSTALL_PREFIX/lib/libtorch.so, libtorch_cpu.so, libc10.so, libonnx*.so

Pass --pytorch "$INSTALL_PREFIX" to build_pytorch_qemu_riscv.sh.
EOF
