import Foundation
import Testing
@testable import BatteryETA

let yasnoSample = """
{"19.1":{"today":{"slots":[{"start":0,"end":480,"type":"NotPlanned"},{"start":480,"end":690,"type":"Definite"},{"start":690,"end":1440,"type":"NotPlanned"}],"date":"2026-10-15T00:00:00+03:00","status":"ScheduleApplies"},"tomorrow":{"slots":[{"start":0,"end":1440,"type":"NotPlanned"}],"date":"2026-10-16T00:00:00+03:00","status":"WaitingForSchedule"},"updatedOn":"2026-10-15T02:24:56+00:00"}}
"""

func kyiv(_ text: String) -> Date {
    let format = DateFormatter()
    format.calendar = Schedule.kyiv
    format.timeZone = Schedule.kyiv.timeZone
    format.dateFormat = "yyyy-MM-dd HH:mm"
    return format.date(from: text)!
}

struct ScheduleTests {
    private func day(_ ymd: String, _ status: String = "ScheduleApplies", off: [(Int, Int)] = [], type: String = "Definite") -> ScheduleDay {
        ScheduleDay(date: kyiv("\(ymd) 00:00"), status: status, slots: off.map { ScheduleSlot(start: $0.0, end: $0.1, type: type) })
    }

    private func days(today: ScheduleDay, tomorrow: ScheduleDay? = nil) -> GroupDays {
        GroupDays(today: today, tomorrow: tomorrow ?? day("2026-10-16", "WaitingForSchedule"))
    }

    @Test func decodesTheLiveFeed() throws {
        let days = try #require(try Schedule.decode(Data(yasnoSample.utf8), key: "19.1"))
        #expect(days.today.status == "ScheduleApplies")
        #expect(days.today.slots[1] == ScheduleSlot(start: 480, end: 690, type: "Definite"))
        #expect(days.today.date == kyiv("2026-10-15 00:00"))
        #expect(try Schedule.decode(Data(yasnoSample.utf8), key: "19") == nil)
    }

    @Test func anotherMalformedGroupDoesNotBreakOurs() throws {
        let feed = #"{"1.1":{"today":{"slots":"broken"}},"2.1":7,"# + yasnoSample.dropFirst()
        let days = try #require(try Schedule.decode(Data(feed.utf8), key: "19.1"))
        #expect(days.today.slots[1] == ScheduleSlot(start: 480, end: 690, type: "Definite"))
    }

    @Test func groupKeysMatchTheFeed() {
        #expect(OutageGroup(group: 19, subgroup: 1, address: "").key == "19.1")
        #expect(OutageGroup(group: 5, subgroup: 0, address: "").key == "5")
    }

    @Test(arguments: ["2026-10-15 07:00", "2026-10-15 09:00"])
    func theCurrentOrNextSlotCounts(now: String) {
        let answer = Schedule.answer(days(today: day("2026-10-15", off: [(480, 690), (1020, 1230)])), now: kyiv(now))
        #expect(answer == .off(from: kyiv("2026-10-15 08:00"), until: kyiv("2026-10-15 11:30")))
    }

    @Test func afterTodaysSlotsTomorrowCounts() {
        let answer = Schedule.answer(days(today: day("2026-10-15", off: [(480, 690)]), tomorrow: day("2026-10-16", off: [(840, 1050)])), now: kyiv("2026-10-15 12:00"))
        #expect(answer == .off(from: kyiv("2026-10-16 14:00"), until: kyiv("2026-10-16 17:30")))
    }

    @Test func aSlotAcrossMidnightEndsTomorrow() {
        let answer = Schedule.answer(days(today: day("2026-10-15", off: [(1260, 1440)]), tomorrow: day("2026-10-16", off: [(0, 120)])), now: kyiv("2026-10-15 22:00"))
        #expect(answer == .off(from: kyiv("2026-10-15 21:00"), until: kyiv("2026-10-16 02:00")))
    }

    @Test func anUnpublishedTomorrowDoesNotCount() {
        let answer = Schedule.answer(days(today: day("2026-10-15", off: [(480, 690)]), tomorrow: day("2026-10-16", "WaitingForSchedule", off: [(840, 1050)])), now: kyiv("2026-10-15 12:00"))
        #expect(answer == .clear)
    }

    @Test func emergencyHasNoEnd() {
        #expect(Schedule.answer(days(today: day("2026-10-15", "EmergencyShutdowns")), now: kyiv("2026-10-15 12:00")) == .emergency)
    }

    @Test func anOutdatedEmergencyDayIsNotAnEmergency() {
        #expect(Schedule.answer(days(today: day("2026-10-15", "EmergencyShutdowns")), now: kyiv("2026-10-17 12:00")) == .clear)
    }

    @Test func possibleSlotsDoNotCount() {
        #expect(Schedule.answer(days(today: day("2026-10-15", off: [(840, 1050)], type: "Possible")), now: kyiv("2026-10-15 12:00")) == .clear)
    }

    @Test func aManualTimeAheadWins() {
        let now = kyiv("2026-10-15 09:00")
        let manual = kyiv("2026-10-15 13:00")
        #expect(Schedule.fill(PowerBack(at: manual, fromSchedule: false), answer: .off(from: now, until: kyiv("2026-10-15 11:30")), now: now) == PowerBack(at: manual, fromSchedule: false))
    }

    @Test func theScheduleFillsAnEmptyOrPassedTime() {
        let now = kyiv("2026-10-15 09:00")
        let filled = PowerBack(at: kyiv("2026-10-15 11:30"), fromSchedule: true)
        let answer = ScheduleAnswer.off(from: now, until: kyiv("2026-10-15 11:30"))
        #expect(Schedule.fill(PowerBack(at: nil, fromSchedule: false), answer: answer, now: now) == filled)
        #expect(Schedule.fill(PowerBack(at: kyiv("2026-10-15 08:00"), fromSchedule: false), answer: answer, now: now) == filled)
    }

    @Test(arguments: [ScheduleAnswer.clear, .emergency, nil] as [ScheduleAnswer?])
    func aScheduleTimeGoesWithItsSlot(answer: ScheduleAnswer?) {
        let now = kyiv("2026-10-15 09:00")
        #expect(Schedule.fill(PowerBack(at: kyiv("2026-10-15 11:30"), fromSchedule: true), answer: answer, now: now) == PowerBack(at: nil, fromSchedule: false))
    }

    @Test func noScheduleLeavesAManualTime() {
        let manual = PowerBack(at: kyiv("2026-10-15 08:00"), fromSchedule: false)
        #expect(Schedule.fill(manual, answer: nil, now: kyiv("2026-10-15 09:00")) == manual)
    }
}

actor URLLog {
    var urls: [URL] = []
    func add(_ url: URL) { urls.append(url) }
}

struct FeedTests {
    private func store() -> Store {
        let store = scratchStore()
        store.settings = BatterySettings(host: "192.168.68.50", port: 30000, floorPct: 12)
        store.outageGroup = OutageGroup(group: 19, subgroup: 1, address: "вул. Хрещатик, 1")
        return store
    }

    private func client(_ log: URLLog, reply: String = yasnoSample) -> YasnoClient {
        YasnoClient { url in
            await log.add(url)
            return Data(reply.utf8)
        }
    }

    @Test func aTickFillsTheSlotEnd() async {
        let store = store()
        let changed = await ScheduleFeed.tick(store, now: kyiv("2026-10-15 09:00"), client: client(URLLog()))
        #expect(changed)
        #expect(store.powerBack == kyiv("2026-10-15 11:30"))
        #expect(store.powerBackFromSchedule)
    }

    @Test func theFeedReadsAtMostEvery30Minutes() async {
        let store = store()
        let log = URLLog()
        let start = kyiv("2026-10-15 07:00")
        for minutes in [0.0, 10, 29, 31] {
            _ = await ScheduleFeed.tick(store, now: start.addingTimeInterval(minutes * 60), client: client(log))
        }
        #expect(await log.urls.count == 2)
        store.outageGroup = OutageGroup(group: 20, subgroup: 1, address: "вул. Хрещатик, 2")
        _ = await ScheduleFeed.tick(store, now: start.addingTimeInterval(32 * 60), client: client(log))
        #expect(await log.urls.count == 3)
    }

    @Test func aFailedReadKeepsTheLastSchedule() async {
        let store = store()
        let start = kyiv("2026-10-15 07:00")
        _ = await ScheduleFeed.tick(store, now: start, client: client(URLLog()))
        let failing = YasnoClient { _ in throw URLError(.notConnectedToInternet) }
        _ = await ScheduleFeed.tick(store, now: start.addingTimeInterval(31 * 60), client: failing)
        #expect(store.schedule?.failed == true)
        #expect(store.schedule?.days != nil)
        #expect(store.powerBack == kyiv("2026-10-15 11:30"))
    }

    @Test func noGroupReadsNothing() async {
        let store = store()
        store.outageGroup = nil
        let log = URLLog()
        let changed = await ScheduleFeed.tick(store, now: kyiv("2026-10-15 09:00"), client: client(log))
        #expect(!changed)
        #expect(await log.urls.isEmpty)
    }

    @Test(arguments: [("вулиця Хрещатик", "Хрещатик"), ("проспект Перемоги", "Перемоги"), ("бульвар Лесі Українки", "Лесі Українки"), ("Хрещатик", "Хрещатик")])
    func aStreetIsSearchedWithoutItsType(street: String, query: String) {
        #expect(Address.query(street) == query)
    }

    @Test func aStreetMatchesItsYasnoName() {
        let streets = [YasnoChoice(id: 599, value: "вул. Набережно-Хрещатицька"), YasnoChoice(id: 1013, value: "вул. Хрещатик")]
        #expect(Address.match("вулиця Хрещатик", in: streets)?.id == 1013)
        #expect(Address.match("Хрещ", in: streets) == nil)
        #expect(Address.match("10А", in: [YasnoChoice(id: 1, value: "10"), YasnoChoice(id: 2, value: "10а")])?.id == 2)
    }

    @Test(arguments: [(#"{"group":19,"subgroup":1}"#, 1), ("19", 0)])
    func aGroupReplyDecodes(reply: String, subgroup: Int) async throws {
        let group = try await client(URLLog(), reply: reply).group(street: 1013, house: 42494)
        #expect(group.group == 19)
        #expect(group.subgroup == subgroup)
    }
}
