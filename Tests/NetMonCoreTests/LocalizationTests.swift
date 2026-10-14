import Foundation
import Testing
@testable import NetMonCore

@Suite("Interface language")
struct LocalizationTests {
    @Test("Existing installs default to Chinese and unknown values safely fall back")
    func defaultLanguage() throws {
        let name = "NetMonTests.Language.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preference = LanguagePreference(defaults: defaults)
        #expect(preference.language == .chinese)
        defaults.set("unsupported", forKey: LanguagePreference.key)
        #expect(preference.language == .chinese)
    }

    @Test("Language choice survives preference recreation and does not change tracking settings")
    func persistence() throws {
        let name = "NetMonTests.Language.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "trackWiFi")
        defaults.set(true, forKey: "trackEthernet")
        let preference = LanguagePreference(defaults: defaults)
        preference.language = .english
        let reopened = try #require(UserDefaults(suiteName: name))
        #expect(LanguagePreference(defaults: reopened).language == .english)
        #expect(!reopened.bool(forKey: "trackWiFi"))
        #expect(reopened.bool(forKey: "trackEthernet"))
        preference.language = .chinese
        #expect(LanguagePreference(defaults: reopened).language == .chinese)
    }

    @Test("Both catalogs preserve every interpolation placeholder")
    func catalog() {
        let regex = try! NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ text: String) -> [String] {
            let source = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: source.length))
                .map { source.substring(with: $0.range) }.sorted()
        }
        for (key, english) in L10n.english {
            #expect(!english.isEmpty)
            #expect(placeholders(key) == placeholders(english))
            #expect(english.range(of: #"\p{Han}"#, options: .regularExpression) == nil)
            #expect(L10n.text(key, language: .chinese) == key)
            #expect(L10n.text(key, language: .english) == english)
        }
    }

    @Test("Formatting preserves Chinese names, braces, percent signs and multiline error details")
    func interpolation() {
        let detail = "家庭网络 {1} 100%\n第二行"
        #expect(L10n.format("无法读取 {0} 的接口计数器（错误 {1}）",
            arguments: [detail, "42"], language: .english)
            == "Unable to read interface counters for \(detail) (error 42)")
        #expect(L10n.format("无法读取 {0} 的接口计数器（错误 {1}）",
            arguments: [detail, "42"], language: .chinese)
            == "无法读取 \(detail) 的接口计数器（错误 42）")
    }

    @Test("Unsupported text passes through without rewriting user data")
    func passthrough() {
        let name = "家里 Wi-Fi {0}"
        #expect(L10n.text(name, language: .english) == name)
        #expect(L10n.text("Ethernet", language: .english) == "Ethernet")
    }

    @Test("History date presentation uses the selected locale without changing day keys")
    func dateLocale() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let key = DayKey.string(for: date)
        let chinese = date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(AppLanguage.chinese.locale))
        let english = date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(AppLanguage.english.locale))
        #expect(chinese != english)
        #expect(DayKey.string(for: date) == key)
    }
}
