#ifndef OBFUSCATION_VMPTAGGER_H
#define OBFUSCATION_VMPTAGGER_H

namespace llvm {
class ModulePass;
class PassRegistry;
class ObfuscationOptions;

ModulePass *createVMPTaggerPass(ObfuscationOptions *argsOptions);
void        initializeVMPTaggerPass(PassRegistry &Registry);

} // namespace llvm

#endif
