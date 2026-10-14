import Foundation

struct BatterySettings: Codable, Equatable {
    var host = ""
    var port = 30000
    var floorPct = 12

    var problem: String? {
        if host.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) == nil { return String(localized: "Enter the battery IP address") }
        if !(1...65535).contains(port) { return String(localized: "Port must be 1 to 65535") }
        if !(0...50).contains(floorPct) { return String(localized: "Reserve must be 0 to 50 %") }
        return nil
    }
}

enum FetchError: String, Codable {
    case settings, blocked, noLink, badReply

    init(_ error: Error) {
        switch error as? DeviceError {
        case .blocked: self = .blocked
        case .badReply: self = .badReply
        default: self = .noLink
        }
    }

    var text: String {
        switch self {
        case .settings: String(localized: "SET IP")
        case .blocked: String(localized: "ALLOW LAN")
        case .noLink: String(localized: "NO LINK")
        case .badReply: String(localized: "ERROR")
        }
    }
}

struct Snapshot: Codable, Equatable {
    var reading: Reading?
    var error: FetchError?
    var checkedAt: Date
}

final class Store {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.id)) {
        self.defaults = defaults ?? .standard
    }

    var settings: BatterySettings {
        get { load("settings") ?? BatterySettings() }
        set { save(newValue, "settings") }
    }

    var snapshot: Snapshot? {
        get { load("snapshot") }
        set { save(newValue, "snapshot") }
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        defaults.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}

enum Refresher {
    static func refresh(
        _ store: Store,
        now: Date = .now,
        fetch: (BatterySettings) async throws -> Reading = Refresher.live
    ) async -> Snapshot {
        let settings = store.settings
        var next = Snapshot(reading: store.snapshot?.reading, error: nil, checkedAt: now)
        if settings.problem != nil {
            next.error = .settings
        } else {
            do { next.reading = try await fetch(settings) } catch { next.error = FetchError(error) }
        }
        store.snapshot = next
        return next
    }

    static func live(_ settings: BatterySettings) async throws -> Reading {
        try await MarstekClient(host: settings.host, port: UInt16(settings.port)).reading()
    }
}
