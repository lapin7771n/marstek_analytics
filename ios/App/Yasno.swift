import Foundation

struct YasnoChoice: Codable, Hashable, Identifiable {
    var id: Int
    var value: String
}

struct YasnoClient {
    static let base = URL(string: "https://app.yasno.ua/api/blackout-service/public/shutdowns/")!
    static let region = 25
    static let dso = 902

    var get: @Sendable (URL) async throws -> Data = YasnoClient.live

    static func live(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    func planned(_ key: String) async throws -> GroupDays? {
        try Schedule.decode(await get(Self.base.appending(path: "regions/\(Self.region)/dsos/\(Self.dso)/planned-outages")), key: key)
    }

    func streets(_ query: String) async throws -> [YasnoChoice] {
        try await list("addresses/v2/streets", ["query": query])
    }

    func houses(street: Int, query: String) async throws -> [YasnoChoice] {
        try await list("addresses/v2/houses", ["streetId": "\(street)", "query": query])
    }

    func group(street: Int, house: Int) async throws -> (group: Int, subgroup: Int) {
        let data = try await get(url("addresses/v2/group", ["streetId": "\(street)", "houseId": "\(house)"]))
        struct Reply: Decodable { var group: Int; var subgroup: Int? }
        if let reply = try? JSONDecoder().decode(Reply.self, from: data) { return (reply.group, reply.subgroup ?? 0) }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        guard let group = Int(text) else { throw URLError(.cannotParseResponse) }
        return (group, 0)
    }

    private func list(_ path: String, _ query: [String: String]) async throws -> [YasnoChoice] {
        try JSONDecoder().decode([YasnoChoice].self, from: await get(url(path, query)))
    }

    private func url(_ path: String, _ query: [String: String]) -> URL {
        let items = [URLQueryItem(name: "regionId", value: "\(Self.region)"), URLQueryItem(name: "dsoId", value: "\(Self.dso)")]
            + query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Self.base.appending(path: path).appending(queryItems: items)
    }
}

enum ScheduleFeed {
    static func tick(_ store: Store, now: Date = .now, client: YasnoClient = YasnoClient()) async -> Bool {
        var state = store.schedule
        if let group = store.outageGroup {
            let age = state.map { now.timeIntervalSince($0.checkedAt) } ?? .infinity
            if state?.key != group.key || !(0..<Schedule.readEvery).contains(age) {
                let kept = state?.key == group.key ? state?.days : nil
                do {
                    state = ScheduleState(key: group.key, checkedAt: now, days: try await client.planned(group.key))
                } catch {
                    state = ScheduleState(key: group.key, checkedAt: now, days: kept, failed: true)
                }
                store.schedule = state
            }
        } else {
            state = nil
        }
        let current = PowerBack(at: store.powerBack, fromSchedule: store.powerBackFromSchedule)
        let next = Schedule.fill(current, answer: state?.days.map { Schedule.answer($0, now: now) }, now: now)
        guard next != current else { return false }
        store.powerBack = next.at
        store.powerBackFromSchedule = next.fromSchedule
        return true
    }
}

enum Address {
    private static let types: Set<String> = ["вулиця", "вул.", "проспект", "просп.", "бульвар", "бульв.", "провулок", "пров.", "площа", "пл.", "набережна", "наб.", "узвіз", "шосе", "алея", "проїзд", "тупик", "майдан"]

    static func query(_ street: String) -> String {
        street.split(separator: " ").filter { !types.contains($0.lowercased()) }.joined(separator: " ")
    }

    static func match(_ name: String, in choices: [YasnoChoice]) -> YasnoChoice? {
        let wanted = query(name).lowercased()
        let exact = choices.filter { query($0.value).lowercased() == wanted }
        return exact.count == 1 ? exact[0] : nil
    }
}
