# iOS ARM64 runtime boundary

This directory contains the native ARM64 iOS boundary for the Java runtime:

- `NekoCraftRuntimeBridge.swift` provides a Metal-backed rendering surface.
- `NekoCraftJavaRuntime.h` defines the native JavaVM/JNI lifecycle API.
- `NekoCraftJavaRuntime.c` loads `libjvm.dylib` and calls `JNI_CreateJavaVM`.
- `package-runtime.sh` copies and signs the ARM64 runtime inside an app bundle.

Fetch the ARM64 iOS Java 21 runtime published by the upstream OpenJDK build with:

```sh
make -C Runtime ios-jre21
```

The runtime is stored in `Runtime/src/depends/java-21-openjdk/` and is ignored by Git because it is a large generated binary payload. Package and sign it with `Runtime/ios/package-runtime.sh RUNTIME_DIRECTORY APP_BUNDLE SIGNING_IDENTITY`. JIT still requires a supported sideload method and device-side activation; an ordinary App Store IPA cannot enable it.