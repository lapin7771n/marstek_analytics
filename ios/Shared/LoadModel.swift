import Foundation

// Ridge regression of the backup-socket load on the hour of day, weekend and the load just before.
struct LoadModel: Codable, Equatable {
    static let minDays = 7
    static let window: TimeInterval = 28 * 24 * 3600
    static let lambda = 1.0
    static let recentSpan: TimeInterval = 3 * 3600
    static let terms = 26

    var weights: [Double]
    var days: Int
    var fittedAt: Date

    static func fit(_ samples: [Sample], now: Date, calendar: Calendar = .current) -> LoadModel? {
        let rows = samples
            .compactMap { s in s.offgridW.map { (time: s.time, watts: Double($0)) } }
            .filter { now.timeIntervalSince($0.time) <= window && $0.time <= now }
            .sorted { $0.time < $1.time }
        let days = Set(rows.map { calendar.startOfDay(for: $0.time) }).count
        guard days >= minDays else { return nil }

        var prefix = [0.0]
        for row in rows { prefix.append(prefix[prefix.count - 1] + row.watts) }
        let overall = prefix[rows.count] / Double(rows.count)

        var gram = [[Double]](repeating: [Double](repeating: 0, count: terms), count: terms)
        var moment = [Double](repeating: 0, count: terms)
        var first = 0, last = 0
        for (i, row) in rows.enumerated() {
            while rows[first].time < row.time.addingTimeInterval(-recentSpan) { first += 1 }
            while last < i, rows[last].time < row.time { last += 1 }
            let recent = last > first ? (prefix[last] - prefix[first]) / Double(last - first) : overall
            let x = features(at: row.time, recentW: recent, calendar: calendar)
            for a in 0..<terms {
                moment[a] += x[a] * row.watts
                for b in 0..<terms { gram[a][b] += x[a] * x[b] }
            }
        }
        for a in 0..<terms { gram[a][a] += lambda }
        guard let weights = solve(gram, moment) else { return nil }
        return LoadModel(weights: weights, days: days, fittedAt: now)
    }

    func watts(at time: Date, recentW: Double, calendar: Calendar = .current) -> Double {
        let x = Self.features(at: time, recentW: recentW, calendar: calendar)
        return max(0, zip(weights, x).reduce(0) { $0 + $1.0 * $1.1 })
    }

    private static func features(at time: Date, recentW: Double, calendar: Calendar) -> [Double] {
        var x = [Double](repeating: 0, count: terms)
        x[calendar.component(.hour, from: time)] = 1
        let weekday = calendar.component(.weekday, from: time)
        x[24] = weekday == 1 || weekday == 7 ? 1 : 0
        x[25] = recentW / 1000
        return x
    }

    // Gaussian elimination with partial pivoting.
    private static func solve(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        let n = vector.count
        var m = zip(matrix, vector).map { $0.0 + [$0.1] }
        for col in 0..<n {
            guard let pivot = (col..<n).max(by: { abs(m[$0][col]) < abs(m[$1][col]) }), abs(m[pivot][col]) > 1e-12 else { return nil }
            m.swapAt(col, pivot)
            for row in (col + 1)..<max(col + 1, n) {
                let factor = m[row][col] / m[col][col]
                if factor == 0 { continue }
                for k in col...n { m[row][k] -= factor * m[col][k] }
            }
        }
        var w = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = m[row][n]
            for k in (row + 1)..<max(row + 1, n) { sum -= m[row][k] * w[k] }
            w[row] = sum / m[row][row]
        }
        return w
    }
}
