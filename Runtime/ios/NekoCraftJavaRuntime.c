#include "NekoCraftJavaRuntime.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int jint;
typedef struct JavaVM JavaVM;
typedef struct JNIEnv JNIEnv;

typedef struct {
    char *optionString;
    void *extraInfo;
} JavaVMOption;

typedef struct {
    jint version;
    jint nOptions;
    JavaVMOption *options;
    jint ignoreUnrecognized;
} JavaVMInitArgs;

typedef jint (*JNI_CreateJavaVMFunction)(JavaVM **, void **, void *);

struct NekoCraftJavaRuntime {
    char *runtimeHome;
    void *jvmLibrary;
    JavaVM *jvm;
};

NekoCraftJavaRuntime *NekoCraftJavaRuntimeCreate(const char *runtimeHome) {
    if (runtimeHome == NULL) {
        return NULL;
    }

    NekoCraftJavaRuntime *runtime = calloc(1, sizeof(*runtime));
    if (runtime == NULL) {
        return NULL;
    }

    size_t length = strlen(runtimeHome);
    runtime->runtimeHome = malloc(length + 1);
    if (runtime->runtimeHome == NULL) {
        free(runtime);
        return NULL;
    }

    memcpy(runtime->runtimeHome, runtimeHome, length + 1);
    return runtime;
}

int NekoCraftJavaRuntimeStart(NekoCraftJavaRuntime *runtime, int argc, const char *argv[]) {
    return NekoCraftJavaRuntimeLaunch(runtime, "net.minecraft.client.main.Main", NULL, argc, argv);
}

int NekoCraftJavaRuntimeLaunchMinecraft(NekoCraftJavaRuntime *runtime, const char *classPath, const char *username, const char *version, const char *gameDirectory, const char *assetsDirectory, const char *assetIndex) {
    const char *arguments[] = {
        "--username", username,
        "--version", version,
        "--gameDir", gameDirectory,
        "--assetsDir", assetsDirectory,
        "--assetIndex", assetIndex,
        "--uuid", "00000000-0000-0000-0000-000000000000",
        "--accessToken", "0",
        "--userType", "legacy",
        "--versionType", "release"
    };
    return NekoCraftJavaRuntimeLaunch(runtime, "net.minecraft.client.main.Main", classPath, (int)(sizeof(arguments) / sizeof(arguments[0])), arguments);
}

int NekoCraftJavaRuntimeLaunch(NekoCraftJavaRuntime *runtime, const char *mainClass, const char *classPath, int argc, const char *argv[]) {
    if (runtime == NULL || runtime->runtimeHome == NULL || mainClass == NULL || classPath == NULL) {
        return -1;
    }
    if (runtime->jvm != NULL) {
        return 0;
    }

    (void)mainClass;
    (void)argc;
    (void)argv;
    size_t pathLength = strlen(runtime->runtimeHome) + strlen("/lib/server/libjvm.dylib") + 1;
    char *jvmPath = malloc(pathLength);
    if (jvmPath == NULL) {
        return -1;
    }
    snprintf(jvmPath, pathLength, "%s/lib/server/libjvm.dylib", runtime->runtimeHome);
    runtime->jvmLibrary = dlopen(jvmPath, RTLD_NOW | RTLD_LOCAL);
    free(jvmPath);
    if (runtime->jvmLibrary == NULL) {
        return -1;
    }

    JNI_CreateJavaVMFunction createVM = (JNI_CreateJavaVMFunction)dlsym(runtime->jvmLibrary, "JNI_CreateJavaVM");
    if (createVM == NULL) {
        dlclose(runtime->jvmLibrary);
        runtime->jvmLibrary = NULL;
        return -1;
    }

    char homeOption[4096];
    snprintf(homeOption, sizeof(homeOption), "-Djava.home=%s", runtime->runtimeHome);
    JavaVMOption options[2] = {
        { homeOption, NULL },
        { NULL, NULL }
    };
    char classPathOption[4096];
    if (classPath != NULL) {
        snprintf(classPathOption, sizeof(classPathOption), "-Djava.class.path=%s", classPath);
        options[1].optionString = classPathOption;
    }

    JavaVMInitArgs initArgs = { 0x00010008, classPath == NULL ? 1 : 2, options, 1 };
    void *environment = NULL;
    if (createVM(&runtime->jvm, &environment, &initArgs) != 0) {
        dlclose(runtime->jvmLibrary);
        runtime->jvmLibrary = NULL;
        return -1;
    }

    return 0;
}

void NekoCraftJavaRuntimeStop(NekoCraftJavaRuntime *runtime) {
    (void)runtime;
}

void NekoCraftJavaRuntimeDestroy(NekoCraftJavaRuntime *runtime) {
    if (runtime == NULL) {
        return;
    }

    free(runtime->runtimeHome);
    if (runtime->jvmLibrary != NULL) {
        dlclose(runtime->jvmLibrary);
    }
    free(runtime);
}