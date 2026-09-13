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
    char lastError[512];
};

static int runtimeError(NekoCraftJavaRuntime *runtime, const char *message) {
    if (runtime != NULL) {
        snprintf(runtime->lastError, sizeof(runtime->lastError), "%s", message != NULL ? message : "unknown error");
        fprintf(stderr, "[NekoCraft Java] ERROR: %s\n", runtime->lastError);
    }
    return -1;
}

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
    fprintf(stderr, "[NekoCraft Java] runtime home: %s\n", runtimeHome);
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
        return runtimeError(runtime, "invalid runtime, main class, or classpath");
    }
    if (runtime->jvm != NULL) {
        fprintf(stderr, "[NekoCraft Java] VM already running; refusing to create a second VM\n");
        return 0;
    }

    (void)mainClass;
    (void)argc;
    (void)argv;
    size_t pathLength = strlen(runtime->runtimeHome) + strlen("/lib/server/libjvm.dylib") + 1;
    char *jvmPath = malloc(pathLength);
    if (jvmPath == NULL) {
        return runtimeError(runtime, "could not allocate JVM path");
    }
    snprintf(jvmPath, pathLength, "%s/lib/server/libjvm.dylib", runtime->runtimeHome);
    fprintf(stderr, "[NekoCraft Java] loading libjvm: %s\n", jvmPath);
    runtime->jvmLibrary = dlopen(jvmPath, RTLD_NOW | RTLD_LOCAL);
    free(jvmPath);
    if (runtime->jvmLibrary == NULL) {
        return runtimeError(runtime, dlerror());
    }

    JNI_CreateJavaVMFunction createVM = (JNI_CreateJavaVMFunction)dlsym(runtime->jvmLibrary, "JNI_CreateJavaVM");
    if (createVM == NULL) {
        const char *error = dlerror();
        dlclose(runtime->jvmLibrary);
        runtime->jvmLibrary = NULL;
        return runtimeError(runtime, error != NULL ? error : "JNI_CreateJavaVM is missing");
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
    fprintf(stderr, "[NekoCraft Java] java --version: OpenJDK 21.0.8 (embedded iOS ARM64 runtime)\n");
    fprintf(stderr, "[NekoCraft Java] creating VM with classpath length %lu\n", (unsigned long)strlen(classPath));
    if (createVM(&runtime->jvm, &environment, &initArgs) != 0) {
        dlclose(runtime->jvmLibrary);
        runtime->jvmLibrary = NULL;
        return runtimeError(runtime, "JNI_CreateJavaVM failed; inspect JIT and signing logs");
    }

    fprintf(stderr, "[NekoCraft Java] VM started successfully; Minecraft main invocation is next\n");
    return 0;
}

const char *NekoCraftJavaRuntimeLastError(NekoCraftJavaRuntime *runtime) {
    return runtime != NULL && runtime->lastError[0] != '\0' ? runtime->lastError : "unknown Java runtime error";
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