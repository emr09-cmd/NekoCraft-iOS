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

if [ -n "$signing_identity" ] && [ "$signing_identity" != "-" ] && [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
    find "$destination" -type f -print0 | while IFS= read -r -d '' file; do
        if file "$file" | grep -q 'Mach-O'; then
            codesign --force --sign "$signing_identity" --timestamp=none "$file"
        fi
    done
else
    echo "Runtime copied without signing. Pass an Apple signing identity to sign Mach-O files."
fi

echo "ARM64 Java runtime packaged at $destination"