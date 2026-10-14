#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
# dmg-only repackages an existing verified app, preserving the published ZIP.
mode="${1:-all}"
case "$mode" in
    all) ./Scripts/build.sh app ;;
    dmg-only) [[ -d dist/NetMon.app ]] ;;
    *) echo "Usage: $0 [all|dmg-only]" >&2; exit 2 ;;
esac
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
architecture=$(lipo -archs dist/NetMon.app/Contents/MacOS/NetMon)
if [[ "$architecture" != "arm64" ]]; then
    echo "v0.1.0 release packaging requires arm64; found $architecture" >&2
    exit 1
fi
name="NetMon-${version}-${architecture}"
if [[ "$mode" == "dmg-only" && ! -f "dist/${name}.zip" ]]; then
    echo "Existing ZIP required to preserve release checksums" >&2
    exit 1
fi
codesign --verify --deep --strict dist/NetMon.app
staging=$(mktemp -d "$project_root/.build/dmg-stage.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto dist/NetMon.app "$staging/NetMon.app"
ln -s /Applications "$staging/Applications"
# A clean, path-free Finder layout shows just the app and Applications link.
# The MIT license is already included inside NetMon.app/Contents/Resources.
cp Resources/DMGLayout.store "$staging/.DS_Store"
hdiutil create -ov -volname "NetMon ${version}" -srcfolder "$staging" -format UDZO "dist/${name}.dmg"
hdiutil verify "dist/${name}.dmg"
if [[ "$mode" == "all" ]]; then
    ditto -c -k --sequesterRsrc --keepParent dist/NetMon.app "dist/${name}.zip"
fi
(cd dist && shasum -a 256 "${name}.dmg" "${name}.zip" > SHA256SUMS)
echo "Packaged $mode: DMG and SHA256SUMS in dist/"
