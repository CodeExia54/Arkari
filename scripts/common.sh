#!/usr/bin/env bash
# Shared logic for scripts/build-ubuntu.sh and scripts/build-termux.sh.
# Not meant to be run directly.

set -euo pipefail

ARKARI_REPO_URL="${ARKARI_REPO_URL:-https://github.com/CodeExia54/Arkari.git}"
ARKARI_BRANCH="${ARKARI_BRANCH:-llvm-23.x}"
VMPACKER_REPO_URL="${VMPACKER_REPO_URL:-https://github.com/LeoChen-CoreMind/VMPacker.git}"

WORKDIR="${WORKDIR:-$HOME/arkari-build}"
# ARKARI_DIR may already point at a checkout this script is running from
# (e.g. CI, where actions/checkout already has the monorepo on disk) --
# in that case don't let clone_or_update below pull a second full copy.
ARKARI_DIR="${ARKARI_DIR:-$WORKDIR/Arkari}"
VMPACKER_DIR="${VMPACKER_DIR:-$WORKDIR/VMPacker}"
BUILD_DIR="${BUILD_DIR:-$WORKDIR/build}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$WORKDIR/install}"

BUILD_TYPE="${BUILD_TYPE:-Release}"
LLVM_TARGETS="${LLVM_TARGETS:-AArch64;X86}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

log() { echo -e "\033[1;32m[arkari-build]\033[0m $*" >&2; }
warn() { echo -e "\033[1;33m[arkari-build][warn]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[arkari-build][error]\033[0m $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found (install it first)"
}

# Always start from git: clone fresh if missing, otherwise fetch+reset to
# the tracked branch so a re-run never silently builds stale local edits
# someone forgot about. Edits made directly in these checkouts (like the
# vmp ObfOpt/VMPTagger/toObfuscate changes) are intentionally NOT reset
# here if you point ARKARI_DIR at an existing working tree you're actively
# developing in -- only the default $WORKDIR/Arkari path is treated as a
# disposable build checkout.
clone_or_update() {
  local repo_url="$1" branch="$2" dir="$3"
  if [[ -d "$dir/.git" ]]; then
    log "updating existing checkout: $dir"
    git -C "$dir" fetch --depth 1 origin "$branch"
    git -C "$dir" checkout -q "$branch"
    git -C "$dir" reset -q --hard "origin/$branch"
  else
    log "cloning $repo_url ($branch) -> $dir"
    git clone --depth 1 -b "$branch" "$repo_url" "$dir"
  fi
}

configure_arkari() {
  log "configuring Arkari/LLVM build (targets: $LLVM_TARGETS, type: $BUILD_TYPE)"
  cmake -S "$ARKARI_DIR/llvm" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="$LLVM_TARGETS" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_USE_LINKER=lld \
    "${EXTRA_CMAKE_ARGS[@]:-}"
}

build_arkari() {
  log "building clang + lld with ninja (-j$JOBS); this takes a long time and a lot of RAM"
  ninja -C "$BUILD_DIR" -j"$JOBS" clang lld
}

install_arkari() {
  log "installing Arkari clang/lld to $INSTALL_PREFIX"
  ninja -C "$BUILD_DIR" install-clang install-lld install-clang-resource-headers 2>/dev/null \
    || ninja -C "$BUILD_DIR" install
}

install_vmp_headers_and_wrapper() {
  log "installing arkari/vmp.h and arkari-vmp-link"
  mkdir -p "$INSTALL_PREFIX/include/arkari" "$INSTALL_PREFIX/bin"
  cp "$ARKARI_DIR/include/arkari/vmp.h" "$INSTALL_PREFIX/include/arkari/vmp.h"
  cp "$ARKARI_DIR/utils/arkari/arkari-vmp-link.sh" "$INSTALL_PREFIX/bin/arkari-vmp-link"
  chmod +x "$INSTALL_PREFIX/bin/arkari-vmp-link"
}

build_vmpacker_cli() {
  require_cmd go
  log "building vmpacker CLI (go build)"
  ( cd "$VMPACKER_DIR" && go build -o "$INSTALL_PREFIX/bin/vmpacker" ./cmd/vmpacker/ )
}

# Compiling stub/vm_interp_clean.c needs a real aarch64-linux-gnu (glibc)
# cross toolchain. Returns 1 (and warns) instead of hard-failing, since the
# caller may want to skip this on platforms where that toolchain isn't
# available (see build-termux.sh).
build_vmpacker_stub() {
  local cc="$1" objcopy="$2"
  if ! command -v "$cc" >/dev/null 2>&1; then
    warn "cross compiler '$cc' not found, skipping VM interpreter stub build"
    warn "vmpacker will still build, but needs cmd/vmpacker/vm_interp.bin present (built elsewhere) to actually protect binaries"
    return 1
  fi
  log "compiling VM interpreter stub with $cc"
  ( cd "$VMPACKER_DIR" && \
    "$cc" -Os -nostdlib -fPIC -ffreestanding \
      -o /tmp/arkari-vmp-stub.elf stub/vm_interp_clean.c -T stub/vm_interp.lds && \
    "$objcopy" -O binary /tmp/arkari-vmp-stub.elf cmd/vmpacker/vm_interp.bin && \
    rm -f /tmp/arkari-vmp-stub.elf )
}

print_summary() {
  cat >&2 <<EOF

[arkari-build] done.
  clang/lld prefix : $INSTALL_PREFIX
  vmpacker         : $INSTALL_PREFIX/bin/vmpacker
  arkari-vmp-link  : $INSTALL_PREFIX/bin/arkari-vmp-link
  header           : $INSTALL_PREFIX/include/arkari/vmp.h

Add to your shell profile:
  export PATH="$INSTALL_PREFIX/bin:\$PATH"
  export C_INCLUDE_PATH="$INSTALL_PREFIX/include:\${C_INCLUDE_PATH:-}"
  export CPLUS_INCLUDE_PATH="$INSTALL_PREFIX/include:\${CPLUS_INCLUDE_PATH:-}"

Example:
  #include <arkari/vmp.h>
  VMP_PROTECT
  int check_license(const char *key) { ... }

  clang++ -target aarch64-linux-gnu -mllvm -irobf-vmp \\
          -mllvm -arkari-vmp-manifest=vmp.manifest -c app.cpp -o app.o
  clang++ -target aarch64-linux-gnu app.o -o app
  arkari-vmp-link app vmp.manifest -o app.protected
EOF
}
