import Darwin
import Foundation
import Observation

struct Subnet {
    let address: UInt32
    let mask: UInt32

    var hosts: [String] {
        let mask = mask | 0xFFFF_FC00
        let network = address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        let all = (network + 1..<broadcast).filter { $0 != address }
        let near = all.filter { $0 >> 8 == address >> 8 }
        let far = all.filter { $0 >> 8 != address >> 8 }
        return (near + far).map(Subnet.format)
    }

    static func local() -> [Subnet] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        return sequence(first: first, next: { $0.pointee.ifa_next }).compactMap { entry in
            let item = entry.pointee
            let flags = Int32(item.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let addr = item.ifa_addr, let mask = item.ifa_netmask, addr.pointee.sa_family == UInt8(AF_INET) else { return nil }
            return Subnet(address: ipv4(addr), mask: ipv4(mask))
        }
    }

    static func localHosts() -> [String] {
        var seen = Set<String>()
        return local().flatMap(\.hosts).filter { seen.insert($0).inserted }
    }

    static func parse(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return nil }
        return parts.reduce(0) { $0 << 8 | $1 }
    }

    static func format(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String(value >> $0 & 255) }.joined(separator: ".")
    }

    private static func ipv4(_ pointer: UnsafeMutablePointer<sockaddr>) -> UInt32 {
        pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
    }
}

struct FoundBattery: Equatable, Identifiable, Sendable {
    let host: String
    let model: String
    let mac: String?
    var firmware: Int? = nil
    var id: String { host }

    var macTail: String? {
        guard let hex = mac?.filter(\.isHexDigit).uppercased(), hex.count >= 4 else { return nil }
        return "…:\(hex.suffix(4).prefix(2)):\(hex.suffix(2))"
    }

    var detail: String {
        [host, macTail, firmware.map { "V\($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
}

typealias Probe = @Sendable (String) async throws -> DeviceInfo?

// One request to the battery at a time from this process: the poll and a search share it.
actor BatteryLine {
    static let shared = BatteryLine()
    private var busy = false

    func claim() -> Bool {
        if busy { return false }
        busy = true
        return true
    }

    func take() async throws {
        while !claim() { try await Task.sleep(for: .milliseconds(100)) }
    }

    func release() {
        busy = false
    }
}

enum Discovery {
    static func sweep(
        _ hosts: [String],
        width: Int = 32,
        probe: @escaping Probe,
        found: @escaping @Sendable (FoundBattery) async -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: FoundBattery?.self) { group in
            var pending = hosts.makeIterator()
            func next() {
                guard !Task.isCancelled, let host = pending.next() else { return }
                group.addTask {
                    if Task.isCancelled { return nil }
                    do { return try await probe(host).map { FoundBattery(host: host, model: $0.model, mac: $0.mac, firmware: $0.firmware) } }
                    catch DeviceError.blocked { throw DeviceError.blocked }
                    catch { return nil }
                }
            }
            for _ in 0..<width { next() }
            while let battery = try await group.next() {
                if let battery { await found(battery) }
                next()
            }
        }
    }

    static func live(port: Int) -> Probe {
        let port = UInt16(exactly: port) ?? 30000
        return { host in try await MarstekClient(host: host, port: port, timeout: 1).device() }
    }
}

@MainActor @Observable
final class BatteryFinder {
    enum Outcome { case noWifi, blocked }

    private(set) var searching = false
    private(set) var found: [FoundBattery] = []
    private(set) var outcome: Outcome?
    private(set) var stopped = false
    private var startedAt: Date?
    private var task: Task<Void, Never>?
    private let store: Store
    private let line: BatteryLine
    private let hosts: () -> [String]
    private let now: () -> Date
    private let settle: Duration

    init(
        store: Store = Store(),
        line: BatteryLine = .shared,
        hosts: @escaping () -> [String] = Subnet.localHosts,
        now: @escaping () -> Date = { .now },
        settle: Duration = .seconds(5)
    ) {
        self.store = store
        self.line = line
        self.hosts = hosts
        self.now = now
        self.settle = settle
    }

    func start(_ probe: @escaping Probe) {
        if searching { return }
        if let startedAt, now().timeIntervalSince(startedAt) < 30 { return }
        let hosts = hosts()
        found = []
        outcome = nil
        guard !hosts.isEmpty else { outcome = .noWifi; return }
        startedAt = now()
        searching = true
        stopped = false
        task = Task {
            store.searchUntil = Date.now + 70
            do {
                try await line.take()
            } catch {
                store.searchUntil = nil
                searching = false
                return
            }
            do {
                try await Task.sleep(for: settle)
                try await Discovery.sweep(hosts, probe: probe) { battery in await self.add(battery) }
            } catch is CancellationError {
            } catch {
                outcome = .blocked
                startedAt = nil
            }
            store.searchUntil = nil
            await line.release()
            searching = false
        }
    }

    func stop() {
        if searching { stopped = true }
        task?.cancel()
    }

    func wait() async {
        await task?.value
    }

    private func add(_ battery: FoundBattery) {
        found.append(battery)
        found.sort { Subnet.parse($0.host) ?? 0 < Subnet.parse($1.host) ?? 0 }
    }
}
