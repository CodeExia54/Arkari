#!/usr/bin/env bash
# Build Arkari (OLLVM-based clang) + VMPacker inside Termux (Android).
#
# Known limitation, read before running: VMPacker's VM interpreter stub
# (stub/vm_interp_clean.c) must be compiled with a real aarch64-linux-gnu
# (glibc) cross-compiler. Termux's own toolchain targets Android/bionic,
# and Termux's package repo does not carry a glibc aarch64-linux-gnu
# cross-gcc. This script will try `pkg install aarch64-linux-gnu-gcc`
# anyway in case your Termux repo mirror happens to carry it, but if that
# fails you have two options:
#   1. Build cmd/vmpacker/vm_interp.bin once on a regular Linux machine
#      (e.g. via scripts/build-ubuntu.sh, or just the two commands in
#      VMPacker's README "Compile VM Interpreter Stub" section) and copy
#      that single file into $VMPACKER_DIR/cmd/vmpacker/ before this
#      script's `go build` step runs.
#   2. Run `pkg install proot-distro && proot-distro install ubuntu`,
#      enter that Ubuntu rootfs, and run the stub-compile step there.
# Everything else here (building Arkari's clang, the vmpacker Go CLI,
# arkari-vmp-link, arkari/vmp.h) works natively in Termux.
#
# Also: building a full LLVM/Clang on a phone is heavy. Defaults below
# are tuned down (AArch64-only target, serialized link jobs) to reduce
# peak memory; it will still take a long time and needs several GB free.
#
# Usage:
#   ./scripts/build-termux.sh [--skip-deps] [--skip-install]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${LLVM_TARGETS:=AArch64}"
: "${JOBS:=$(( $(nproc 2>/dev/null || echo 2) > 2 ? $(nproc) - 1 : 1 ))}"
export LLVM_TARGETS JOBS

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

EXTRA_CMAKE_ARGS=(
  "-DLLVM_PARALLEL_LINK_JOBS=1"
)

SKIP_DEPS=0
SKIP_INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --skip-deps) SKIP_DEPS=1 ;;
    --skip-install) SKIP_INSTALL=1 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

if [[ -z "${PREFIX:-}" ]] || [[ "$PREFIX" != *com.termux* ]]; then
  warn "this doesn't look like a Termux environment (\$PREFIX=${PREFIX:-unset}); continuing anyway"
fi

if [[ "$SKIP_DEPS" -eq 0 ]]; then
  log "installing build dependencies (pkg)"
  pkg update -y
  pkg install -y clang cmake ninja git golang make binutils python
  if ! pkg install -y aarch64-linux-gnu-gcc 2>/dev/null; then
    warn "no glibc aarch64-linux-gnu cross-gcc available via pkg -- see the stub-build note at the top of this script"
  fi
else
  log "skipping dependency install (--skip-deps)"
fi

for c in cmake ninja git go clang; do require_cmd "$c"; done

mkdir -p "$WORKDIR"
clone_or_update "$ARKARI_REPO_URL" "$ARKARI_BRANCH" "$ARKARI_DIR"
clone_or_update "$VMPACKER_REPO_URL" master "$VMPACKER_DIR"

configure_arkari
build_arkari

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  install_arkari
  install_vmp_headers_and_wrapper
  build_vmpacker_stub aarch64-linux-gnu-gcc aarch64-linux-gnu-objcopy || true
  build_vmpacker_cli
  print_summary
else
  log "skipping install (--skip-install); built artifacts are under $BUILD_DIR"
fi
