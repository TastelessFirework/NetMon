#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
action="${1:-build}"
configuration="${2:-debug}"
cd "$project_root"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Configuration must be debug or release" >&2
    exit 2
fi
default_sdk="$(xcrun --show-sdk-path)"
sdk_path="${SSID_TRAFFIC_SDK:-$default_sdk}"

# Some early macOS 27 Command Line Tools releases contain a Swift compiler and
# default SDK from different patch builds. The co-installed 26.5 SDK is ABI
# compatible and avoids that packaging defect. Full Xcode installations keep
# using their selected default SDK.
compat_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ "${sdk_path:A}" == "/Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk" && -d "$compat_sdk" ]]; then
    sdk_path="$compat_sdk"
fi

export SDKROOT="$sdk_path"
export SWIFT_MODULECACHE_PATH="$project_root/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/clang-cache"
mkdir -p "$SWIFT_MODULECACHE_PATH" "$CLANG_MODULE_CACHE_PATH"

swift_arguments=(--disable-sandbox --sdk "$sdk_path")

create_app_icon() {
    local iconset_path="$project_root/.build/AppIcon.iconset"
    local size
    mkdir -p "$iconset_path"
    for size in 16 32 128 256 512; do
        sips --resampleHeightWidth "$size" "$size" \
            "$project_root/Resources/AppIcon.png" \
            --out "$iconset_path/icon_${size}x${size}.png" >/dev/null
        sips --resampleHeightWidth "$((size * 2))" "$((size * 2))" \
            "$project_root/Resources/AppIcon.png" \
            --out "$iconset_path/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil --convert icns "$iconset_path" \
        --output "$project_root/Resources/AppIcon.icns"
}

create_app_bundle() {
    local app_path="$1"
    local contents_path="$app_path/Contents"

    rm -rf "$app_path"
    mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
    cp "$binary_directory/NetMon" "$contents_path/MacOS/NetMon"
    cp "$project_root/Resources/Info.plist" "$contents_path/Info.plist"
    cp "$project_root/LICENSE" "$contents_path/Resources/LICENSE"
    cp "$project_root/Resources/AppIcon.icns" "$contents_path/Resources/AppIcon.icns"
    codesign --force --sign - "$app_path"
    echo "Created $app_path"
}

case "$action" in
    icon)
        create_app_icon
        ;;

    build)
        swift build "${swift_arguments[@]}" --configuration "$configuration"
        ;;

    test)
        swiftc_path="$(xcrun --find swiftc)"
        testing_plugin="${swiftc_path:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
        plugin_arguments=()
        if [[ -f "$testing_plugin" ]]; then
            plugin_arguments=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
        fi
        swift test "${swift_arguments[@]}" "${plugin_arguments[@]}"
        ;;

    app)
        swift build "${swift_arguments[@]}" --configuration release
        binary_directory="$(swift build "${swift_arguments[@]}" --configuration release --show-bin-path)"
        create_app_bundle "$project_root/dist/NetMon.app"
        ;;

    *)
        echo "Usage: $0 {build|test|app|icon} [debug|release]" >&2
        exit 2
        ;;
esac
