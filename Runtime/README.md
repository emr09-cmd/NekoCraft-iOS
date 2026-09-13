# NekoCraft Java runtime module

This is the Java-side runtime build module. It creates `launcher.jar` and a merged `lwjgl.jar` from the sources and libraries in this directory.

Build it with a JDK:

```sh
make BOOTJDK="$JAVA_HOME"
```

The supplied `lwjgl-3.3.3.jar` is under `libs/lwjgl/`. Build output is written to `build/` and is ignored by Git. The `javaruntime/` directory is reserved for the platform-specific JRE/JDK payload produced by the native iOS runtime build; a desktop JDK must not be copied into an iOS IPA.