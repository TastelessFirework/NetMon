# NetMon v0.1.1 — 中文 / English 切换

本版新增英语界面。在“设置 / Settings”二级菜单顶部提供“中文”和“English”两行，当前语言左侧打勾。选择会保存，无需重启；重新打开菜单即可使用所选语言。新安装和此前未选择过语言的安装默认中文。

主菜单、流量明细、设置、命名与清除确认、应用错误提示、辅助功能文字和历史日期支持中英文。SSID、自定义网络名称、系统网络服务名称保留原文，历史数据、统计设置与登录项选择继续保留。macOS 权限和管理员认证窗口跟随系统语言；应用包提供中英文位置权限用途说明。

## 下载与升级

支持 **macOS 14+、Apple Silicon / arm64**。继续采用 ad-hoc 签名、未进行 Apple 公证，标为 Pre-release。MIT 许可证，署名 Eric。

- `NetMon-0.1.1-arm64.dmg`：打开后将 NetMon 拖入 Applications；保持两个图标左右并排。
- `NetMon-0.1.1-arm64.zip`：解压后将完整应用包放入 Applications。
- `SHA256SUMS`：DMG 与 ZIP 的 SHA-256 校验值。

升级前先退出旧版，再替换应用包。历史数据不随应用包分发，升级保留已有数据；登录时启动默认关闭。

首次打开若被 macOS 阻止，可按系统提示到“系统设置 → 隐私与安全性”选择“仍要打开”。安装、权限、统计边界与数据说明见 [README](https://github.com/TastelessFirework/NetMon/blob/v0.1.1/README.md)。

## 验证与限制

31 项自动测试通过，包含语言默认值、选择持久化、翻译参数与特殊文本处理；离屏 AppKit 菜单检查覆盖两行语言选项、互斥勾选、两种菜单关闭时序和切换后的菜单文字。Release 构建、arm64、最低部署字段 14.0、ad-hoc 签名、双语权限资源、ZIP 与 DMG 中的应用和许可证已校验。

尚未安装或启动本次应用构建；实际菜单悬停、完整网络/权限/登录项功能矩阵及 macOS 14 兼容性仍待实机验收。只统计应用运行期间的主接口流量，切换边界可能少记；VPN 底层接口使用启发式判断。数据库与主动启用的 Debug 文件日志为明文；没有自动更新器。

## English

Choose **中文** or **English** at the top of the **Settings** submenu. The selected language has a checkmark and is remembered. Reopen the menu to see the new language; restarting is unnecessary. Chinese remains the default.

Menus, usage details, app dialogs, app error messages, accessibility text and history dates are localized. Wi-Fi names, custom network names and macOS service names remain unchanged. Your usage history and existing settings are preserved.

Requires **macOS 14+ on Apple Silicon**. This is an **ad-hoc signed, unnotarized pre-release**. Quit the old app before replacing it with the new app. Download the DMG or ZIP above; checksum values are provided in `SHA256SUMS`. Full on-device and minimum-system acceptance testing remains pending.
