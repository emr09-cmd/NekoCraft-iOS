#ifndef NEKOCRAFT_JAVA_RUNTIME_H
#define NEKOCRAFT_JAVA_RUNTIME_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct NekoCraftJavaRuntime NekoCraftJavaRuntime;

NekoCraftJavaRuntime *NekoCraftJavaRuntimeCreate(const char *runtimeHome);
int NekoCraftJavaRuntimeStart(NekoCraftJavaRuntime *runtime, int argc, const char *argv[]);
int NekoCraftJavaRuntimeLaunch(NekoCraftJavaRuntime *runtime, const char *mainClass, const char *classPath, int argc, const char *argv[]);
int NekoCraftJavaRuntimeLaunchMinecraft(NekoCraftJavaRuntime *runtime, const char *classPath, const char *username, const char *version, const char *gameDirectory, const char *assetsDirectory, const char *assetIndex);
void NekoCraftJavaRuntimeStop(NekoCraftJavaRuntime *runtime);
void NekoCraftJavaRuntimeDestroy(NekoCraftJavaRuntime *runtime);

#ifdef __cplusplus
}
#endif

#endif