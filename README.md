# NetMon

<img src="Resources/AppIcon.png" alt="NetMon 图标：蛛网与蓝色独眼怪" width="112">

NetMon 是纯本地的 macOS 菜单栏流量统计工具，按 Wi-Fi SSID 记录上传和下载用量，也支持 Ethernet、PPP/PPPoE、VPN 和其他主网络接口。菜单栏显示实时上传/下载速度与当前网络今日总量，点击展开原生 AppKit 菜单。

当前版本为 **0.1.0 预览版**，功能与安装说明见 [Release 说明](RELEASE_NOTES_v0.1.0.md)。应用使用 ad-hoc 签名，未经过 Apple 公证。

## 下载与快速安装

从 [v0.1.0 Release](https://github.com/TastelessFirework/NetMon/releases/tag/v0.1.0) 下载 **NetMon-0.1.0-arm64.dmg**。打开磁盘映像，只显示 NetMon 与 Applications 两个图标；将 `NetMon.app` 拖入 `Applications` 文件夹，然后从“应用程序”打开。也提供 ZIP 包和 `SHA256SUMS` 校验文件。

这是 **macOS 14+ / Apple Silicon 的预览版**，未经过 Apple 公证；首次打开若被系统阻止，请参考下方安装说明。完整实机与最低支持系统验收尚未完成。

## 界面与功能导览

### 在菜单栏随时查看网速

![NetMon 菜单栏实时上传、下载速度与今日流量](docs/images/menu-bar.png)

左侧两行分别显示实时上传和下载速度；右侧上方显示自定义网络名称（未命名时为 `usage`），下方显示当前网络的今日总流量。无需打开窗口，就能了解网络是否正在传输数据。

### 点击查看流量明细

<img src="docs/images/main-menu.png" alt="NetMon 原生菜单：当前网络、实时网速、今日和本月流量，以及所有网络与设置入口" width="360">

- **当前网络**：查看名称和接口，并通过子菜单查看、调整系统网络服务顺序；真实修改需要管理员认证。
- **实时网速**：上传与下载分别显示，菜单展开期间继续更新。
- **今日 / 本月**：总量、上传、下载分开列出，便于了解用量。
- **所有网络**：查看各网络与全部网络合计的今日、最近 7 天、本月和全部历史。
- **设置**：自定义网络名称、登录时启动、SSID 授权与历史管理；登录时启动默认关闭。
- **Debug**：排查采样问题时查看状态，可选文件日志默认关闭。

以上为实际界面截图；截图中的网速和用量仅展示拍摄时的状态。

## 功能

- 今日、最近 7 天、本月、全部历史的上传、下载和总量，另有所有网络合计。
- Wi-Fi 按 SSID 分组；Ethernet、PPP 等按类型和接口身份分组。
- Wi-Fi、Ethernet、PPP/PPPoE 可设置最多 6 字符的自定义名称，留空恢复默认名称。
- 每秒采样 Darwin 64 位 RX/TX counter，SQLite 通常每 10 秒批量落盘。
- 网络、接口、断线、睡眠、设置变化或 counter 回退时重建 baseline。
- 菜单打开时原位更新数值，网络列表结构变化延迟到主菜单关闭后处理。
- 登录时启动、SSID 授权入口、数据库定位、可选 Debug 文件日志与清除历史。
- 查看 macOS 当前网络服务顺序，选择服务可经管理员认证将其移至首位。

## 系统要求

- macOS 14 或更新版本。
- 当前提供中文界面，尚未提供英文界面。
- v0.1.0 支持 **Apple Silicon（M 系列 Mac）/ arm64**；不提供 Intel 或 Universal 应用。
- 构建需要 Apple Command Line Tools 或完整 Xcode，使用 **Swift 6 或更新版本**（测试使用 Swift Testing；manifest 的 tools-version 为 5.10）。无第三方 SwiftPM 依赖。

## 从源码构建

在项目目录运行：

```bash
make test      # 核心逻辑、SQLite 和本机 loopback counter smoke test
make app       # Release 编译 + dist/NetMon.app + ad-hoc 签名
make package   # 构建并生成 DMG、ZIP 与 SHA256SUMS（不安装、不发布）
```

其他入口为 `make build`（Debug）和 `make release`（Release 可执行文件）。脚本使用项目内的 module cache，并传入 SwiftPM `--disable-sandbox` 以兼容本地工具链；这不代表应用启用了或关闭了 App Sandbox。当前应用没有 App Sandbox entitlement。

脚本默认使用 `xcrun` 选择的 SDK。对于 Command Line Tools 的 macOS 27.0 SDK，脚本会在 26.5 SDK 可用时选择该兼容 SDK。可显式选择 SDK：

```bash
SSID_TRAFFIC_SDK=/path/to/MacOSX.sdk make app
```

这是原生架构构建，输出架构取决于构建主机，不会自动生成 Universal 二进制。

应用图标源图为 `Resources/AppIcon.png`，macOS 图标文件为 `Resources/AppIcon.icns`。`make app` 直接打包 ICNS；修改源图后先运行 `make icon` 重新生成各尺寸图标。

## 安装、更新与卸载

手动将完整的 `dist/NetMon.app` 复制到 `/Applications` 或 `~/Applications`，或运行：

```bash
make install
open ~/Applications/NetMon.app
```

`make install` 默认复制到当前用户的 Applications 目录，可用 `INSTALL_DIR` 覆盖。更新前先从菜单退出正在运行的 NetMon，再覆盖应用包并重新打开；安装不覆盖历史数据库。

**登录时启动默认关闭**，安装版只有在用户主动开启时才注册；从 `dist` 启动的开发版不能注册登录项。升级时保留系统已有的登录项选择，不会自动关闭用户此前启用的登录项。首次启动会请求位置权限以读取 SSID，拒绝后无法识别的 Wi-Fi 暂停统计。

v0.1.0 采用 ad-hoc 签名，未进行 Apple 公证。网络下载后可能被 Gatekeeper 阻止：先尝试打开应用，再到“系统设置 → 隐私与安全性”按系统提示选择“仍要打开”，随后确认“打开”。此流程取决于系统提供的选项，受管理的 Mac 可能不允许放行，具体见 [Apple 打开未公证应用说明](https://support.apple.com/zh-cn/102445)。

卸载时先关闭登录时启动并退出应用，再将 `.app` 移到废纸篓。若需删除本地历史与日志，可在 Finder 中分别移除下面两个目录。清除历史同时删除自定义名称，不可撤销。

## 权限与隐私

| 行为 | 权限及数据 |
| --- | --- |
| 读取 Wi-Fi SSID | CoreWLAN + Core Location 授权；只请求授权，不启动位置更新，不保存经纬度 |
| 读取流量 | Darwin `NET_RT_IFLIST2` 的 64 位接口字节计数器，无逐包捕获 |
| 修改网络服务顺序 | Security Authorization + SystemConfiguration；每次真实修改创建授权，结束后销毁，不缓存管理员密码 |
| 登录时启动 | `SMAppService.mainApp`；默认关闭，用户主动开启才注册；升级保留已有状态 |
| Debug | 菜单显示真实 SSID；系统日志消息标为 private，主动启用的文件日志仍为明文 |

应用不上传数据，不含账号、广告、Telemetry、测速或自动更新服务。运行时数据不随应用包分发：

```text
~/Library/Application Support/SSIDTrafficMonitor/usage.sqlite3
~/Library/Logs/SSIDTrafficMonitor/debug.log
```

数据库含真实 SSID、网络自定义名称、接口、使用时间与字节总量，未加密。Debug 文件日志默认关闭，启用后包含 SSID、接口、时间戳及采样差值，当前没有日志轮转。不要将数据库、日志或未脱敏的 Debug 截图提交到 GitHub；关闭文件日志不会删除既有文件。

Bundle ID 保留 `com.eric.SSIDTrafficMonitor`，数据目录和设置也保留旧标识以兼容已有安装。更换标识需要迁移验证。

## 统计边界与已知限制

- 只记录应用运行期间的主接口流量，不补记停机期间；异常退出可能丢失约 10 秒未落盘数据。
- 同名 SSID 会合并，即使来自不同地点或 AP；不按 BSSID 区分。Ethernet/PPP 主要按接口分组，不表示不同运营商或线路。
- 只在区间两端网络 key 和接口相同、counter 不回退、单调时间差在 0–15 秒内时归属。切换边界主动丢弃，可能少记；公开 API 非原子读取，未证明切换瞬间绝无误归属。
- VPN 优先统计推断的底层 Wi-Fi/Ethernet，含隧道开销；`availableInterfaces` 的首个物理接口是启发式选择，多接口、分流 VPN 和 IPv4/IPv6 不同路径仍需实机验证。
- 按本地日期记账；跨午夜采样区间全部记到区间结束日，没有逐秒拆分。
- 这是接口统计，不是逐应用或运营商计费账单，也不统计全部接口的并行流量。
- 数据库无法初始化时当前会退出；磁盘满、数据库损坏、极端整数边界的恢复体验仍待完善。
- 系统服务顺序修改会影响整个 Mac；提交成功但应用或回读失败时可能已改变配置，失败提示不保证回滚。

## 测试与项目结构

自动测试包含 25 项用例，覆盖归属边界、SQLite 持久化与聚合、自定义命名、网络服务排序、用量汇总和 Darwin counter 读取。实机 Wi-Fi A/B、Ethernet、睡眠唤醒、菜单悬停、授权取消、服务排序和登录项验收按 [TESTING.md](TESTING.md) 执行；自动测试不能代替实机验收。

| 路径 | 职责 |
| --- | --- |
| `Sources/CNetworkStats` | Darwin 64 位接口计数器 C 封装 |
| `Sources/NetMonCore` | 归属状态机、SQLite、用量汇总、纯服务排序逻辑 |
| `Sources/NetMon` | AppKit 菜单、网络解析、授权、登录项与采样调度 |
| `Resources/Info.plist` | 版本、Bundle ID、最低系统版本、位置用途说明 |
| `Scripts/build.sh` | SDK 选择、测试、编译与应用打包 |
| `Scripts/package.sh` | arm64 校验、DMG/ZIP 分发包与 SHA-256 校验文件 |

## 许可证与发布

项目采用 [MIT 许可证](LICENSE)，版权署名为 `Copyright (c) 2026 Eric`。构建包内包含许可证副本。
