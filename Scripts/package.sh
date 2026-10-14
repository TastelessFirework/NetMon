#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
./Scripts/build.sh app
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
architecture=$(lipo -archs dist/NetMon.app/Contents/MacOS/NetMon)
if [[ "$architecture" != "arm64" ]]; then
    echo "v0.1.0 release packaging requires arm64; found $architecture" >&2
    exit 1
fi
name="NetMon-${version}-${architecture}"
codesign --verify --deep --strict dist/NetMon.app
staging=$(mktemp -d "$project_root/.build/dmg-stage.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto dist/NetMon.app "$staging/NetMon.app"
ln -s /Applications "$staging/Applications"
cp LICENSE "$staging/LICENSE"
cat > "$staging/安装说明.txt" <<'TXT'
NetMon v0.1.0 预览版
系统要求：macOS 14+、Apple Silicon（M 系列 Mac）。
将 NetMon.app 拖入 Applications 文件夹，然后从应用程序中打开。
采用 ad-hoc 签名，未经过 Apple 公证。若被系统阻止，首次尝试打开后
可根据系统提示前往“系统设置 → 隐私与安全性 → 仍要打开”。
首次启动需要位置授权以读取 Wi-Fi 名称；登录时启动默认关闭。
更新时先退出旧版本，再替换应用。历史数据保留。
项目与说明：https://github.com/TastelessFirework/NetMon
TXT
hdiutil create -ov -volname "NetMon ${version}" -srcfolder "$staging" -format UDZO "dist/${name}.dmg"
hdiutil verify "dist/${name}.dmg"
ditto -c -k --sequesterRsrc --keepParent dist/NetMon.app "dist/${name}.zip"
(cd dist && shasum -a 256 "${name}.dmg" "${name}.zip" > SHA256SUMS)
echo "Created DMG, ZIP and SHA256SUMS in dist/"
