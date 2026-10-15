import Foundation

struct Sample: Codable, Equatable {
    var time: Date
    var socPct: Int
    var acW: Int

    enum CodingKeys: String, CodingKey { case time = "t", socPct = "s", acW = "w" }
}

extension Sample {
    init(_ r: Reading) {
        self.init(time: r.time, socPct: r.socPct, acW: Int(r.acW.rounded()))
    }
}

struct History: Codable, Equatable {
    static let keep: TimeInterval = 48 * 3600
    static let spacing: TimeInterval = 5 * 60
    static let gap: TimeInterval = 3600

    var samples: [Sample] = []

    mutating func add(_ r: Reading) {
        samples.removeAll { $0.time > r.time || r.time.timeIntervalSince($0.time) > History.keep }
        if let last = samples.last, r.time.timeIntervalSince(last.time) < History.spacing { return }
        samples.append(Sample(r))
    }
}
