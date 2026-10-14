#include "llvm/Transforms/Obfuscation/VMPTagger.h"
#include "llvm/Transforms/Obfuscation/ObfuscationOptions.h"
#include "llvm/Transforms/Utils/ModuleUtils.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/ADT/SmallVector.h"

#define DEBUG_TYPE "vmp_tagger"

using namespace llvm;

namespace {
// Marks functions annotated with `+vmp` so that a post-link step can hand
// them to an external VM-packing tool by symbol name. This pass does not
// obfuscate anything itself: by the time a binary-level VM packer runs,
// there is no IR left. Its job is purely to (1) make sure a tagged
// function's symbol survives to the final link unmolested (not inlined,
// not GC'd), and (2) record its final symbol name in a manifest file that
// the build driver passes to the packer.
class VMPTagger : public ModulePass {
protected:
  ObfuscationOptions *ArgsOptions;

public:
  static char ID;

  explicit VMPTagger(ObfuscationOptions *argsOptions) : ModulePass(ID) {
    this->ArgsOptions = argsOptions;
    initializeVMPTaggerPass(*PassRegistry::getPassRegistry());
  }

  StringRef getPassName() const override {
    return "VMPTagger";
  }

  bool runOnModule(Module &M) override {
    SmallVector<GlobalValue *, 8> Tagged;
    SmallVector<std::string, 8>   TaggedNames;

    for (Function &F : M) {
      if (F.isDeclaration()) {
        continue;
      }
      if (!ObfuscationOptions::toObfuscate(ArgsOptions->vmpOpt(), &F).isEnabled()) {
        continue;
      }

      if (F.hasLocalLinkage()) {
        F.getContext().diagnose(DiagnosticInfoUnsupported{
            F,
            F.getName() +
            " is marked +vmp but has internal linkage; its symbol name "
            "may not be stable enough for the VM packer to find it. "
            "Consider giving it external linkage or a stable alias."});
      }

      // Prevent inlining/DCE from making the function disappear (or merging
      // it with another) before the packer ever sees it as a distinct
      // native-code symbol. Ordinary optimizations are still allowed to
      // run on its body; only its identity as a standalone symbol matters.
      F.addFnAttr(Attribute::NoInline);

      Tagged.push_back(&F);
      TaggedNames.push_back(F.getName().str());
    }

    if (Tagged.empty()) {
      return false;
    }

    appendToUsed(M, Tagged);
    writeManifest(TaggedNames);
    return true;
  }

  void writeManifest(const SmallVector<std::string, 8> &Names) {
    const auto &Path = ArgsOptions->vmpManifestPath();
    if (Path.empty()) {
      return;
    }
    std::error_code      EC;
    raw_fd_ostream Out(Path, EC, sys::fs::OF_Append | sys::fs::OF_Text);
    if (EC) {
      report_fatal_error("Unable to open -arkari-vmp-manifest file '" +
                          Twine(Path) + "': " + EC.message());
    }
    for (const auto &Name : Names) {
      Out << Name << "\n";
    }
  }

  bool doFinalization(Module &) override {
    return false;
  }
};
} // namespace

char VMPTagger::ID = 0;

ModulePass *llvm::createVMPTaggerPass(ObfuscationOptions *argsOptions) {
  return new VMPTagger(argsOptions);
}

INITIALIZE_PASS(VMPTagger, "vmp_tagger",
                 "Tag +vmp annotated functions for post-link VM packing",
                 false, false)
