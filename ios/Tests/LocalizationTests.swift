import Foundation
import Testing
@testable import BatteryETA

struct LocalizationTests {
    private let catalog = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../Shared/Localizable.xcstrings")

    @Test func everyStringHasUkrainian() throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: [String: Any]])
        #expect(strings.count >= 85)
        for (key, entry) in strings {
            let uk = (entry["localizations"] as? [String: Any])?["uk"] as? [String: Any]
            let value = (uk?["stringUnit"] as? [String: Any])?["value"] as? String
            #expect(value?.isEmpty == false, "No Ukrainian for \(key)")
        }
    }

    @Test func theAppShipsUkrainian() throws {
        let path = try #require(Bundle.main.path(forResource: "uk", ofType: "lproj"))
        let uk = try #require(Bundle(path: path))
        #expect(uk.localizedString(forKey: "NO LINK", value: nil, table: nil) == "НЕМАЄ ЗВʼЯЗКУ")
        #expect(uk.localizedString(forKey: "h", value: nil, table: nil) == "год")
        #expect(uk.localizedString(forKey: "−%lld W", value: nil, table: nil) == "−%lld Вт")
        #expect(uk.localizedString(forKey: "%@ kWh", value: nil, table: nil) == "%@ кВт·год")
        #expect(uk.localizedString(forKey: "Privacy policy", value: nil, table: nil) == "Політика конфіденційності")
        #expect(uk.localizedString(forKey: "Support", value: nil, table: nil) == "Підтримка")
        #expect(uk.localizedString(forKey: "LOGS", value: nil, table: nil) == "ЖУРНАЛ")
        #expect(uk.localizedString(forKey: "Copy", value: nil, table: nil) == "Копіювати")
        #expect(uk.localizedString(forKey: "Copied", value: nil, table: nil) == "Скопійовано")
        #expect(uk.localizedString(forKey: "Debug info", value: nil, table: nil) == "Технічні дані")
    }
}
