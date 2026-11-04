#!/bin/bash
set -euo pipefail
if [ "$#" -ne 4 ]; then
    echo "Usage: bash package_local.sh SOURCE_APP SHERPA_WHEEL_DIRECTORY MODEL_ONNX DESTINATION_APP" >&2
    exit 2
fi
source_app="$1"
sherpa="$2"
model="$3"
destination="$4"
checksum=5ef208a9da1453335308a6b6f4e6dfbd7e183a38b604de0a57664f45d257fe94
actual="$(/usr/bin/shasum -a 256 "$model" | /usr/bin/cut -d ' ' -f 1)"
[[ "$actual" == "$checksum" ]] || { echo "Speaker model checksum mismatch" >&2; exit 1; }
[[ ! -e "$destination" ]] || { echo "Destination already exists" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
python3 "$root/Tools/Telugu/prepare_local_app.py" --source "$source_app" --destination "$destination"
frameworks="$destination/Contents/Frameworks"
resources="$destination/Contents/Resources"
cp "$sherpa/lib/libsherpa-onnx-c-api.dylib" "$sherpa/lib/libonnxruntime.dylib" "$frameworks/"
/usr/bin/install_name_tool -change @rpath/libonnxruntime.dylib @loader_path/libonnxruntime.dylib "$frameworks/libsherpa-onnx-c-api.dylib"
cp "$model" "$resources/wespeaker.onnx"
/usr/bin/codesign --force --sign - "$frameworks/libonnxruntime.dylib"
/usr/bin/codesign --force --sign - "$frameworks/libsherpa-onnx-c-api.dylib"
/usr/bin/codesign --force --sign - --options runtime --preserve-metadata=entitlements "$destination"
/usr/bin/codesign --verify --deep --strict "$destination"
