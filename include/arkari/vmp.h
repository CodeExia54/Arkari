#ifndef ARKARI_VMP_H
#define ARKARI_VMP_H

// Tags a function so that Arkari's VMPTagger pass (enabled with
// `-mllvm -irobf-vmp`) records it for post-link VM packing by VMPacker,
// and so Arkari auto-suppresses the redundant fla/icall/indbr passes on it
// (see ObfuscationOptions::toObfuscate's hasVmpTag handling).
//
// Usage:
//   #include <arkari/vmp.h>
//
//   VMP_PROTECT
//   int check_license(const char *key) { ... }
//
// This expands to __attribute__((annotate("+vmp"))), the same convention
// Arkari's other per-function flags (+fla, +icall, ...) use, so it composes
// with them, e.g. `__attribute__((annotate("+vmp +cie")))`.
//
// Compiling without -mllvm -irobf-vmp (or with a non-Arkari compiler) is
// harmless: `annotate` is a standard Clang/GCC attribute that is otherwise
// a no-op, it does not change calling convention, linkage or codegen on
// its own.
#if defined(__clang__) || defined(__GNUC__)
#define VMP_PROTECT __attribute__((annotate("+vmp")))
// VMP_PROTECT_WITH(extra) lets you combine +vmp with other per-function
// annotation flags in one attribute, e.g. VMP_PROTECT_WITH("+cie ^cie=3").
#define VMP_PROTECT_WITH(extra) __attribute__((annotate("+vmp " extra)))
#else
#define VMP_PROTECT
#define VMP_PROTECT_WITH(extra)
#endif

#endif // ARKARI_VMP_H
