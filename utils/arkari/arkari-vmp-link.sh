#!/usr/bin/env bash
# arkari-vmp-link - post-link glue between Arkari and VMPacker.
#
# Arkari's VMPTagger pass (-mllvm -irobf-vmp) records the symbol names of
# every +vmp annotated function into a manifest file at compile time
# (-mllvm -arkari-vmp-manifest=<path>). This script reads that manifest
# after the normal clang link step and hands the matching function names
# to VMPacker, which rewrites the already-linked ELF in place of a
# separate link step:
#
#   clang++ -target aarch64-linux-gnu -mllvm -irobf-vmp \
#           -mllvm -arkari-vmp-manifest=vmp.manifest -c app.cpp -o app.o
#   clang++ -target aarch64-linux-gnu app.o -o app            # plain ELF
#   arkari-vmp-link app vmp.manifest -o app.protected          # VM-pack it
#
# If the manifest is empty or missing, the input is copied through
# unchanged (nothing was tagged +vmp, so there's nothing to do) rather
# than failing the build.
#
# Env vars:
#   VMPACKER_BIN   path to the vmpacker binary (default: "vmpacker" on PATH)
#
# Usage:
#   arkari-vmp-link <input-elf> <manifest-file> -o <output-elf> [-- extra vmpacker args...]

set -euo pipefail

VMPACKER_BIN="${VMPACKER_BIN:-vmpacker}"

usage() {
  echo "usage: $(basename "$0") <input-elf> <manifest-file> -o <output-elf> [-- extra vmpacker args...]" >&2
  exit 1
}

[[ $# -ge 4 ]] || usage

INPUT="$1"
MANIFEST="$2"
shift 2

[[ "${1:-}" == "-o" ]] || usage
OUTPUT="$2"
shift 2

EXTRA_ARGS=()
if [[ "${1:-}" == "--" ]]; then
  shift
  EXTRA_ARGS=("$@")
fi

[[ -f "$INPUT" ]] || { echo "error: input ELF '$INPUT' not found" >&2; exit 1; }

# De-duplicate and drop blank lines; manifest may have been appended to
# across multiple translation units, including the same symbol more than
# once if it was recompiled.
NAMES=""
if [[ -f "$MANIFEST" ]]; then
  NAMES="$(awk 'NF' "$MANIFEST" | sort -u | paste -sd, -)"
fi

if [[ -z "$NAMES" ]]; then
  echo "arkari-vmp-link: no +vmp tagged functions in '$MANIFEST', passing '$INPUT' through unchanged" >&2
  cp -f "$INPUT" "$OUTPUT"
  chmod +x "$OUTPUT"
  exit 0
fi

if ! command -v "$VMPACKER_BIN" >/dev/null 2>&1; then
  echo "error: vmpacker binary not found (looked for '$VMPACKER_BIN'; set VMPACKER_BIN or add it to PATH)" >&2
  exit 1
fi

echo "arkari-vmp-link: protecting functions: $NAMES" >&2
exec "$VMPACKER_BIN" -func "$NAMES" -o "$OUTPUT" "${EXTRA_ARGS[@]}" "$INPUT"
