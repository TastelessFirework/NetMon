import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    public var locale: Locale {
        Locale(identifier: rawValue)
    }
}

public struct LanguagePreference {
    public static let key = "interfaceLanguage"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var language: AppLanguage {
        get {
            defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:))
                ?? .chinese
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.key)
        }
    }
}

/// Only app-owned text is translated. Network names and persisted identities stay intact.
public enum L10n {
    public static var language: AppLanguage { LanguagePreference().language }

    public static func text(_ key: String, language: AppLanguage? = nil) -> String {
        (language ?? self.language) == .english ? english[key] ?? key : key
    }

    public static func format(_ key: String, _ arguments: String...) -> String {
        format(key, arguments: arguments, language: language)
    }

    public static func format(
        _ key: String, arguments: [String], language: AppLanguage
    ) -> String {
        // One pass keeps user text such as "{1}" from becoming another placeholder.
        let template = text(key, language: language)
        let source = template as NSString
        var result = template
        let matches = placeholderPattern.matches(
            in: template, range: NSRange(location: 0, length: source.length)
        )
        for match in matches.reversed() {
            guard let index = Int(source.substring(with: match.range(at: 1))),
                  arguments.indices.contains(index),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[index])
        }
        return result
    }

    private static let placeholderPattern = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)

    static let english: [String: String] = [
        "当前网络": "Current Network",
        "展开 macOS 网络服务顺序": "Show macOS network service order",
        "未识别": "Unidentified",
        "当前上传速度  0 B/s": "Upload Speed  0 B/s",
        "当前下载速度  0 B/s": "Download Speed  0 B/s",
        "今日": "Today",
        "本月": "This Month",
        "所有网络": "All Networks",
        "设置": "Settings",
        "退出 NetMon": "Quit NetMon",
        "网络设置…": "Network Settings…",
        "网络设置": "Network Settings",
        "正在读取网络服务顺序…": "Reading network service order…",
        "当前没有可排序的网络服务": "No network services to reorder",
        "将此服务移到 macOS 网络服务顺序第一位": "Move this service to the top of the macOS network service order",
        "此系统网络服务当前已停用；仍可调整其服务顺序": "This service is disabled; its service order can still be changed",
        "无法读取网络服务顺序": "Unable to read network service order",
        "启动时自动运行": "Launch at Login",
        "统计 Wi-Fi": "Track Wi-Fi",
        "统计 Ethernet": "Track Ethernet",
        "自定义网络名称": "Custom Network Names",
        "SSID 位置权限：尚未请求": "SSID Location Access: Not Requested",
        "允许读取 SSID…": "Allow SSID Access…",
        "在 Finder 中显示数据库": "Show Database in Finder",
        "此操作无法撤销": "This cannot be undone",
        "确认清除": "Confirm Clear",
        "清除历史数据…": "Clear History…",
        "State: 等待第一次采样": "State: Waiting for first sample",
        "写入调试日志": "Write Debug Log",
        "在 Finder 中显示调试日志": "Show Debug Log in Finder",
        "总流量  0 B": "Total  0 B",
        "上传  0 B": "Upload  0 B",
        "下载  0 B": "Download  0 B",
        "当前上传速度  {0}": "Upload Speed  {0}",
        "当前下载速度  {0}": "Download Speed  {0}",
        "总流量  {0}": "Total  {0}",
        "上传  {0}": "Upload  {0}",
        "下载  {0}": "Download  {0}",
        "所有网络  ": "All Networks  ",
        "首次发现 ": "First Seen ",
        "最近 7 天": "Last 7 Days",
        "全部历史": "All Time",
        "所有网络  0 B": "All Networks  0 B",
        "暂无统计": "No Usage Recorded",
        "SSID 位置权限：{0}": "SSID Location Access: {0}",
        "已允许": "Allowed",
        "暂无 Wi-Fi、Ethernet 或 PPP 记录": "No Wi-Fi, Ethernet or PPP Records",
        "只读信息": "Read-only information",
        "已重新读取并显示 macOS 当前实际服务顺序。": "The current macOS service order has been reloaded and displayed.",
        "同时无法重新读取当前服务顺序：": "The current service order also could not be reloaded: ",
        "无法更改网络服务顺序": "Unable to Change Network Service Order",
        "好": "OK",
        "最多 {0} 个字符，": "Up to {0} characters. ",
        "超出部分会自动截断；留空可恢复默认名称。": "Extra characters are truncated; leave blank to restore the default name.",
        "保存": "Save",
        "取消": "Cancel",
        "尚未请求": "Not Requested",
        "受系统限制": "Restricted by System",
        "已拒绝": "Denied",
        "未知": "Unknown",
        "请先将 NetMon 安装到“应用程序”，再从应用包启动。": "Install NetMon in Applications and launch the app first.",
        "错误码 {0}": "Error code {0}",
        "无法创建 macOS 授权会话：{0}。": "Unable to create a macOS authorization session: {0}.",
        "管理员授权已取消或未通过，macOS 未允许{0}。": "Administrator authorization was cancelled or denied. macOS did not allow this operation: {0}.",
        "无法读取 macOS 网络服务顺序：{0}。": "Unable to read macOS network service order: {0}.",
        "macOS 未能{0}：{1}（错误码 {2}）。": "macOS could not perform this operation: {0}: {1} (error code {2}).",
        "系统报告配置已提交并应用，但重新读取时未能确认结果：{0}。": "The system reported that the configuration was committed and applied, but verification failed: {0}.",
        "建立网络配置读取会话": "create a network configuration read session",
        "建立已授权的网络配置会话": "create an authorized network configuration session",
        "所选服务已不在当前系统服务顺序中": "The selected service is no longer in the current system service order",
        "保存新的网络服务顺序": "save the new network service order",
        "提交网络服务顺序": "commit the network service order",
        "应用网络服务顺序": "apply the network service order",
        "首位服务仍不是所选服务": "The selected service is still not first in the service order",
        "当前没有可用的 network set": "No network set is currently available",
        "当前 network set 没有可读取的服务列表": "The current network set has no readable service list",
        "当前 network set 没有可读取的服务顺序": "The current network set has no readable service order",
        "系统返回了重复的服务 ID {0}": "The system returned duplicate service ID {0}",
        "服务顺序引用了当前服务列表中不存在的 ID": "The service order references an ID missing from the current service list",
        "服务 {0} 缺少系统显示名称": "Service {0} has no system display name",
        "系统服务列表与服务顺序暂时不一致": "The system service list and service order are temporarily inconsistent",
        "无法读取 {0} 的接口计数器（错误 {1}）": "Unable to read interface counters for {0} (error {1})",
        "无法打开数据库：{0}": "Unable to open database: {0}",
        "数据库错误：{0}": "Database error: {0}",
        "NetMon，当前网络 {0}，上传速度 {1}，": "NetMon, current network {0}, upload speed {1}, ",
        "下载速度 {0}，": "download speed {0}, ",
        "当前网络今日总流量 {0}": "current network total today {0}",
        "等待第一次采样": "Waiting for first sample",
        "所选 Wi-Fi、Ethernet 或 PPP 尚不可命名。": "The selected Wi-Fi, Ethernet or PPP network cannot be named yet.",
        "已恢复当前网络的默认名称。": "The default network name has been restored.",
        "当前网络名称已保存。": "The network name has been saved.",
        "启用调试日志并等待一次采样后才会创建日志文件。": "Enable debug logging and wait for a sample to create the log file.",
        "历史数据已清除。": "History has been cleared.",
        "已在设置中暂停此网络类型的统计": "Tracking for this network type is paused in Settings",
        "当前没有可用的主网络接口": "No primary network interface is available",
        "无法读取 Wi-Fi 名称；请允许位置权限": "Unable to read Wi-Fi name; allow location access",
        "其他": "Other",
        "其他网络": "Other Network",
    ]
}
