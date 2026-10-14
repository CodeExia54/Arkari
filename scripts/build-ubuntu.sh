#!/usr/bin/env bash
# Build Arkari (OLLVM-based clang) + VMPacker on Ubuntu, and wire them
# together with arkari-vmp-link / arkari/vmp.h.
#
# This always starts from a fresh git clone/update (see common.sh's
# clone_or_update) rather than assuming a checkout is already sitting
# around, so re-running this script always builds what's actually on the
# tracked branches.
#
# Usage:
#   ./scripts/build-ubuntu.sh [--skip-deps] [--skip-install]
#
# Tuning via env vars (see scripts/common.sh for the full list):
#   WORKDIR, INSTALL_PREFIX, JOBS, BUILD_TYPE, LLVM_TARGETS

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

SKIP_DEPS=0
SKIP_INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --skip-deps) SKIP_DEPS=1 ;;
    --skip-install) SKIP_INSTALL=1 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

if [[ "$SKIP_DEPS" -eq 0 ]]; then
  log "installing build dependencies (apt, needs sudo)"
  sudo apt-get update -y
  sudo apt-get install -y \
    build-essential cmake ninja-build git python3 \
    clang lld golang-go \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
else
  log "skipping dependency install (--skip-deps)"
fi

for c in cmake ninja git go; do require_cmd "$c"; done

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
