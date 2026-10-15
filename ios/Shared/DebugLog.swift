import Foundation

struct LogLine: Codable, Equatable {
    var time: Date
    var text: String
}

// Recent events, newest last. Kept on the device in the App Group so the widget's lines show too.
struct DebugLog: Codable, Equatable {
    static let limit = 200
    private(set) var lines: [LogLine] = []

    mutating func add(_ text: String, at time: Date = .now) {
        lines.append(LogLine(time: time, text: text))
        lines.sort { $0.time < $1.time }
        if lines.count > Self.limit { lines.removeFirst(lines.count - Self.limit) }
    }

    static func stamp(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: time)
    }

    func text(info: [(String, String)]) -> String {
        let head = info.map { "\($0.0): \($0.1)" }
        let body = lines.reversed().map { "\(Self.stamp($0.time))  \($0.text)" }
        return (head + [""] + body).joined(separator: "\n")
    }
}

extension Store {
    func log(_ text: String, at time: Date = .now) {
        var log = self.log
        log.add(text, at: time)
        self.log = log
    }
}

extension DeviceError: CustomStringConvertible {
    var description: String {
        switch self {
        case .timeout: "no reply (timeout)"
        case .blocked: "Local Network permission denied"
        case .network(let text): "network: \(text)"
        case .badReply(let text): "bad reply: \(text)"
        }
    }
}
