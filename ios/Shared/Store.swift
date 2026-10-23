import Foundation

enum PollSpeed: String, Codable, CaseIterable {
    case fast, medium, infrequent

    var interval: Duration {
        switch self {
        case .fast: .seconds(60)
        case .medium: .seconds(300)
        case .infrequent: .seconds(900)
        }
    }
}

struct BatterySettings: Codable, Equatable {
    var host = ""
    var port = 30000
    var floorPct = 12
    var retryHost: String?
    var speed: PollSpeed?

    var chosenSpeed: PollSpeed {
        get { speed ?? .fast }
        set { speed = newValue }
    }

    var pollInterval: Duration { chosenSpeed.interval }
    // Only Find battery reads the firmware; a typed host may reset under load.
    var retries: Bool { retryHost == host }

    var problem: String? {
        if host.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) == nil || !isIPv4OrName {
            return String(localized: "Enter the battery IP address")
        }
        if !(1...65535).contains(port) { return String(localized: "Port must be 1 to 65535") }
        if !(0...50).contains(floorPct) { return String(localized: "Reserve must be 0 to 50 %") }
        return nil
    }

    private var isIPv4OrName: Bool {
        guard host.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { $0.count <= 3 && (Int($0).map { (0...255).contains($0) } ?? false) }
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

struct AlertState: Codable, Equatable {
    var on = false
    var soonAlerted = false
    var reserveAlerted = false
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

    var alert: AlertState {
        get { load("alert") ?? AlertState() }
        set { save(newValue, "alert") }
    }

    var history: History {
        get { load("history") ?? History() }
        set { save(newValue, "history") }
    }

    var log: DebugLog {
        get { load("log") ?? DebugLog() }
        set { save(newValue, "log") }
    }

    var powerBack: Date? {
        get { load("powerBack") }
        set { save(newValue, "powerBack") }
    }

    var powerBackFromSchedule: Bool {
        get { load("powerBackFromSchedule") ?? false }
        set { save(newValue, "powerBackFromSchedule") }
    }

    var outageGroup: OutageGroup? {
        get { load("outageGroup") }
        set { save(newValue, "outageGroup") }
    }

    var schedule: ScheduleState? {
        get { load("schedule") }
        set { save(newValue, "schedule") }
    }

    var searchUntil: Date? {
        get { load("searchUntil") }
        set { save(newValue, "searchUntil") }
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        defaults.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}

enum Refresher {
    static let widgetMaxAge: TimeInterval = 10 * 60

    static func refresh(
        _ store: Store,
        now: Date = .now,
        maxAge: TimeInterval = 0,
        fetch: (BatterySettings) async throws -> Reading = Refresher.live
    ) async -> Snapshot {
        if let until = store.searchUntil, now < until {
            return store.snapshot ?? Snapshot(reading: nil, error: nil, checkedAt: now)
        }
        let settings = store.settings
        if settings.problem == nil, let last = store.snapshot, last.error != .settings,
           (0..<maxAge).contains(now.timeIntervalSince(last.checkedAt)) {
            store.log("Reused the reading from \(DebugLog.stamp(last.checkedAt))")
            return last
        }
        var next = Snapshot(reading: store.snapshot?.reading, error: nil, checkedAt: now)
        if let problem = settings.problem {
            next.error = .settings
            store.log("Skipped: \(problem)")
        } else {
            do {
                let reading = try await fetch(settings)
                next.reading = reading
                store.history.add(reading)
                store.log("OK: \(reading.socPct) %, \(Int(reading.acW.rounded())) W")
            } catch {
                next.error = FetchError(error)
                store.log("\(next.error?.rawValue ?? "error"): \(error)")
            }
        }
        store.snapshot = next
        return next
    }

    // A tap that retries counts as a key press: it waits for the 60 s floor, as the timer does.
    static func retryAllowed(_ snapshot: Snapshot?, now: Date = .now) -> Bool {
        guard let checked = snapshot?.checkedAt, checked <= now else { return true }
        return now.timeIntervalSince(checked) >= 60
    }

    static func widgetCanReuse(_ snapshot: Snapshot?, now: Date = .now) -> Bool {
        guard let snapshot, snapshot.error != .settings else { return false }
        return (0..<60).contains(now.timeIntervalSince(snapshot.checkedAt))
    }

    static func live(_ settings: BatterySettings) async throws -> Reading {
        var client = MarstekClient(host: settings.host, port: UInt16(settings.port))
        client.retry = settings.retries
        client.trace = { Store().log($1, at: $0) }
        return try await client.reading()
    }
}

// The three widgets reload together; one fetch serves them all.
actor SharedRefresh {
    static let shared = SharedRefresh()
    private var running: Task<Snapshot, Never>?

    func run(_ work: @escaping @Sendable () async -> Snapshot) async -> Snapshot {
        if let running { return await running.value }
        let task = Task { await work() }
        running = task
        let snapshot = await task.value
        running = nil
        return snapshot
    }
}
