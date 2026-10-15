import Foundation

struct OutageGroup: Codable, Equatable {
    var group: Int
    var subgroup: Int
    var address: String

    var key: String { subgroup == 0 ? "\(group)" : "\(group).\(subgroup)" }
}

struct ScheduleSlot: Codable, Equatable {
    var start: Int
    var end: Int
    var type: String
}

struct ScheduleDay: Codable, Equatable {
    var date: Date
    var status: String
    var slots: [ScheduleSlot]
}

struct GroupDays: Codable, Equatable {
    var today: ScheduleDay
    var tomorrow: ScheduleDay
}

struct ScheduleState: Codable, Equatable {
    var key: String
    var checkedAt: Date
    var days: GroupDays?
    var failed = false
}

enum ScheduleAnswer: Equatable {
    case off(from: Date, until: Date)
    case emergency
    case clear
}

struct PowerBack: Equatable {
    var at: Date?
    var fromSchedule: Bool
}

enum Schedule {
    static let readEvery: TimeInterval = 30 * 60

    static let kyiv: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    static func decode(_ data: Data, key: String) throws -> GroupDays? {
        guard let groups = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The feed is not an object"))
        }
        guard let group = groups[key] else { return nil }
        guard let fields = group as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Group \(key) is not an object"))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GroupDays.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    static func answer(_ days: GroupDays, now: Date, calendar: Calendar = kyiv) -> ScheduleAnswer {
        if days.today.status == "EmergencyShutdowns", calendar.isDate(days.today.date, inSameDayAs: now) { return .emergency }
        var spans: [(from: Date, until: Date)] = []
        for day in [days.today, days.tomorrow] where day.status == "ScheduleApplies" {
            for slot in day.slots where slot.type == "Definite" {
                let from = time(slot.start, on: day.date, calendar), until = time(slot.end, on: day.date, calendar)
                if let last = spans.last, from <= last.until {
                    spans[spans.count - 1].until = max(last.until, until)
                } else {
                    spans.append((from, until))
                }
            }
        }
        guard let next = spans.first(where: { $0.until > now }) else { return .clear }
        return .off(from: next.from, until: next.until)
    }

    static func fill(_ current: PowerBack, answer: ScheduleAnswer?, now: Date) -> PowerBack {
        if let at = current.at, at > now, !current.fromSchedule { return current }
        if case let .off(_, until)? = answer { return PowerBack(at: until, fromSchedule: true) }
        return current.fromSchedule ? PowerBack(at: nil, fromSchedule: false) : current
    }

    private static func time(_ minutes: Int, on day: Date, _ calendar: Calendar) -> Date {
        let midnight = calendar.startOfDay(for: day)
        if minutes >= 1440 { return calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight }
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: midnight) ?? midnight
    }
}
