#!/bin/sh
set -eu

runtime_directory=${1:?Usage: package-runtime.sh RUNTIME_DIRECTORY APP_BUNDLE [SIGNING_IDENTITY]}
app_bundle=${2:?Usage: package-runtime.sh RUNTIME_DIRECTORY APP_BUNDLE [SIGNING_IDENTITY]}
signing_identity=${3:-}

if [ ! -f "$runtime_directory/lib/server/libjvm.dylib" ]; then
    echo "Missing ARM64 Java runtime: $runtime_directory/lib/server/libjvm.dylib" >&2
    exit 1
fi

destination="$app_bundle/JavaRuntime"
rm -rf "$destination"
mkdir -p "$destination"
cp -R "$runtime_directory"/* "$destination/"

native_directory=$(CDPATH= cd -- "$(dirname -- "$0")/native" && pwd)
mkdir -p "$app_bundle/Frameworks" "$destination/libs"
cp -R "$native_directory"/*.dylib "$app_bundle/Frameworks/"
cp -R "$(dirname -- "$0")/../libs/caciocavallo"/*.jar "$destination/libs/"
cp -R "$(dirname -- "$0")/../libs/lwjgl"/*.jar "$destination/libs/"

# The upstream JRE uses @rpath for libjli/libjvm. Point the packaged binaries
# at their sibling runtime directories before signing them.
install_name_tool -add_rpath "@loader_path/../lib" "$destination/bin/java" 2>/dev/null || true
for file in "$destination"/lib/*.dylib "$destination"/lib/server/*.dylib; do
    if [ -f "$file" ]; then
        install_name_tool -add_rpath "@loader_path" "$file" 2>/dev/null || true
        install_name_tool -add_rpath "@loader_path/.." "$file" 2>/dev/null || true
        install_name_tool -add_rpath "@loader_path/../../Frameworks" "$file" 2>/dev/null || true
    fi
done

if [ -n "$signing_identity" ] && [ "$signing_identity" != "-" ] && [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
    for file in "$app_bundle"/Frameworks/*.dylib; do
        codesign --force --sign "$signing_identity" --timestamp=none "$file"
    done
    find "$destination" -type f -print0 | while IFS= read -r -d '' file; do
        if file "$file" | grep -q 'Mach-O'; then
            codesign --force --sign "$signing_identity" --timestamp=none "$file"
        fi
    done
else
    echo "Runtime copied without signing. Pass an Apple signing identity to sign Mach-O files."
fi

echo "ARM64 Java runtime packaged at $destination"