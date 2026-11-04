#!/bin/bash
set -euo pipefail
if [ "$#" -ne 2 ]; then
    echo "Usage: bash build_probe.sh SHERPA_INSTALL OUTPUT_DIRECTORY" >&2
    exit 2
fi
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
sherpa="$(cd "$1" && pwd)"
mkdir -p "$2"
output="$(cd "$2" && pwd)"

xcrun swiftc -swift-version 6 -O -emit-module -emit-library -module-name Domain \
    "$root/Packages/WesleyFlowCore/Sources/Domain/SpeakerRecognition.swift" \
    -emit-module-path "$output/Domain.swiftmodule" -o "$output/libDomain.dylib" \
    -Xlinker -install_name -Xlinker '@rpath/libDomain.dylib'
xcrun swiftc -swift-version 6 -strict-concurrency=complete -O \
    -I "$here/CSherpaOnnx" -Xcc "-I$sherpa/include" -I "$output" \
    -L "$output" -lDomain -L "$sherpa/lib" \
    -Xlinker -rpath -Xlinker "$sherpa/lib" -Xlinker -rpath -Xlinker '@loader_path' \
    "$here/WeSpeakerEngine.swift" "$here/Probe.swift" -o "$output/probe"
