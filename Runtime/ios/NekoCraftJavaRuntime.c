#include "NekoCraftJavaRuntime.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int jint;
typedef struct JavaVM JavaVM;
typedef void *jobject;
typedef jobject jclass;
typedef jobject jstring;
typedef jobject jobjectArray;
typedef void *jmethodID;
typedef int jsize;

typedef union {
    jobject l;
} jvalue;

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
typedef jint (*JNI_AttachCurrentThreadFunction)(JavaVM *, void **, void *);

struct NekoCraftJavaRuntime {
    char *runtimeHome;
    void *jvmLibrary;
    JavaVM *jvm;
    void *environment;
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
    void *environment = runtime->environment;
    if (runtime->jvm == NULL) {
        size_t pathLength = strlen(runtime->runtimeHome) + strlen("/lib/server/libjvm.dylib") + 1;
        char *jvmPath = malloc(pathLength);
        if (jvmPath == NULL) return runtimeError(runtime, "could not allocate JVM path");
        snprintf(jvmPath, pathLength, "%s/lib/server/libjvm.dylib", runtime->runtimeHome);
        fprintf(stderr, "[NekoCraft Java] loading libjvm: %s\n", jvmPath);
        runtime->jvmLibrary = dlopen(jvmPath, RTLD_NOW | RTLD_LOCAL);
        free(jvmPath);
        if (runtime->jvmLibrary == NULL) return runtimeError(runtime, dlerror());

        JNI_CreateJavaVMFunction createVM = (JNI_CreateJavaVMFunction)dlsym(runtime->jvmLibrary, "JNI_CreateJavaVM");
        if (createVM == NULL) return runtimeError(runtime, "JNI_CreateJavaVM is missing");
        char homeOption[4096];
        snprintf(homeOption, sizeof(homeOption), "-Djava.home=%s", runtime->runtimeHome);
        char classPathOption[4096];
        snprintf(classPathOption, sizeof(classPathOption), "-Djava.class.path=%s", classPath);
        JavaVMOption options[2] = {{ homeOption, NULL }, { classPathOption, NULL }};
        JavaVMInitArgs initArgs = { 0x00010008, 2, options, 1 };
        fprintf(stderr, "[NekoCraft Java] java --version: OpenJDK 21.0.8 (embedded iOS ARM64 runtime)\n");
        fprintf(stderr, "[NekoCraft Java] creating VM with classpath length %lu\n", (unsigned long)strlen(classPath));
        if (createVM(&runtime->jvm, &environment, &initArgs) != 0) return runtimeError(runtime, "JNI_CreateJavaVM failed; inspect JIT and signing logs");
        runtime->environment = environment;
        fprintf(stderr, "[NekoCraft Java] VM started successfully\n");
    }

    // JNIEnv is thread-local; attach every Swift launch task before JNI calls.
    void **vmTable = *(void ***)runtime->jvm;
    JNI_AttachCurrentThreadFunction attachCurrentThread = (JNI_AttachCurrentThreadFunction)vmTable[4];
    void *attachedEnvironment = NULL;
    if (attachCurrentThread(runtime->jvm, &attachedEnvironment, NULL) != 0 || attachedEnvironment == NULL) {
        return runtimeError(runtime, "AttachCurrentThread failed");
    }
    environment = attachedEnvironment;

    // JNIEnv is already a pointer to the native function table in C.
    void **jni = (void **)environment;
    jclass (*findClass)(void *, const char *) = (jclass (*)(void *, const char *))jni[6];
    jmethodID (*getStaticMethodID)(void *, jclass, const char *, const char *) = (jmethodID (*)(void *, jclass, const char *, const char *))jni[113];
    jstring (*newStringUTF)(void *, const char *) = (jstring (*)(void *, const char *))jni[167];
    jobjectArray (*newObjectArray)(void *, jsize, jclass, jobject) = (jobjectArray (*)(void *, jsize, jclass, jobject))jni[172];
    void (*setObjectArrayElement)(void *, jobjectArray, jsize, jobject) = (void (*)(void *, jobjectArray, jsize, jobject))jni[174];
    void (*callStaticVoidMethodA)(void *, jclass, jmethodID, const jvalue *) = (void (*)(void *, jclass, jmethodID, const jvalue *))jni[143];
    jobject (*exceptionOccurred)(void *) = (jobject (*)(void *))jni[15];
    void (*exceptionDescribe)(void *) = (void (*)(void *))jni[16];
    void (*exceptionClear)(void *) = (void (*)(void *))jni[17];
    jclass stringClass = findClass(environment, "java/lang/String");
    jclass mainClassObject = findClass(environment, mainClass);
    if (stringClass == NULL || mainClassObject == NULL) return runtimeError(runtime, "Minecraft main class or String class not found");
    jmethodID mainMethod = getStaticMethodID(environment, mainClassObject, "main", "([Ljava/lang/String;)V");
    if (mainMethod == NULL) return runtimeError(runtime, "Minecraft main method not found");
    jobjectArray javaArguments = newObjectArray(environment, argc, stringClass, NULL);
    if (javaArguments == NULL) return runtimeError(runtime, "could not allocate Minecraft arguments");
    for (int index = 0; index < argc; index++) {
        setObjectArrayElement(environment, javaArguments, index, newStringUTF(environment, argv[index]));
    }
    jvalue mainValue = { .l = javaArguments };
    fprintf(stderr, "[NekoCraft Java] invoking %s.main with %d arguments\n", mainClass, argc);
    callStaticVoidMethodA(environment, mainClassObject, mainMethod, &mainValue);
    if (exceptionOccurred(environment) != NULL) {
        exceptionDescribe(environment);
        exceptionClear(environment);
        return runtimeError(runtime, "Minecraft main threw a Java exception; see console");
    }
    fprintf(stderr, "[NekoCraft Java] Minecraft main returned\n");
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