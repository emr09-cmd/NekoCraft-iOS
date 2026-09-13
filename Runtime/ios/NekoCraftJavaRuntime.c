#include "NekoCraftJavaRuntime.h"

#include <dlfcn.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <sys/wait.h>

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
    pid_t processID;
};

extern char **environ;

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
    if (runtime->processID > 0) {
        return 0;
    }

    size_t javaPathLength = strlen(runtime->runtimeHome) + strlen("/bin/java") + 1;
    char *javaPath = malloc(javaPathLength);
    if (javaPath == NULL) return -1;
    snprintf(javaPath, javaPathLength, "%s/bin/java", runtime->runtimeHome);

    size_t argumentCount = (size_t)argc + 4;
    char **arguments = calloc(argumentCount, sizeof(char *));
    if (arguments == NULL) {
        free(javaPath);
        return -1;
    }
    size_t index = 0;
    arguments[index++] = javaPath;
    arguments[index++] = "-cp";
    arguments[index++] = (char *)classPath;
    arguments[index++] = (char *)mainClass;
    for (int argumentIndex = 0; argumentIndex < argc; argumentIndex++) {
        arguments[index++] = (char *)argv[argumentIndex];
    }
    arguments[index] = NULL;

    int result = posix_spawn(&runtime->processID, javaPath, NULL, NULL, arguments, environ);
    free(arguments);
    free(javaPath);
    if (result != 0) {
        runtime->processID = 0;
        return -result;
    }
    return 0;
#if 0
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
#endif
}

void NekoCraftJavaRuntimeStop(NekoCraftJavaRuntime *runtime) {
    if (runtime != NULL && runtime->processID > 0) {
        kill(runtime->processID, SIGTERM);
        waitpid(runtime->processID, NULL, 0);
        runtime->processID = 0;
    }
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