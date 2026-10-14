import Foundation

struct EsStatus: Equatable {
    let socPct: Int
    let ongridW: Double
    let offgridW: Double
    let ratedWh: Double
}

enum MarstekProtocol {
    // The firmware echoes only the low 16 bits of the id and ignores 65535; the retry sends id + 1.
    static func newId() -> Int { Int.random(in: 1...32_766) }

    static func request(id: Int, method: String) -> Data {
        Data(#"{"id":\#(id),"method":"\#(method)","params":{"id":0}}"#.utf8)
    }

    static func replyId(_ data: Data) throws -> Int {
        guard let head = try? JSONDecoder().decode(Head.self, from: data) else { throw DeviceError.badReply("Reply has no id") }
        return head.id
    }

    static func esStatus(_ data: Data) throws -> EsStatus {
        let result = try decode(EsResult.self, data)
        guard result.ratedWh > 0 else { throw DeviceError.badReply("Reply has bat_cap \(result.ratedWh)") }
        return EsStatus(socPct: Int(result.socPct.rounded()), ongridW: result.ongridW, offgridW: result.offgridW, ratedWh: result.ratedWh)
    }

    private static func decode<R: Decodable>(_ type: R.Type, _ data: Data) throws -> R {
        guard let envelope = try? JSONDecoder().decode(Envelope<R>.self, from: data) else {
            throw DeviceError.badReply("Reply has a missing field")
        }
        if let fault = envelope.error { throw DeviceError.badReply("Device error \(fault.code): \(fault.message)") }
        guard let result = envelope.result else { throw DeviceError.badReply("Reply has no result") }
        return result
    }
}

private struct Head: Decodable {
    let id: Int
}

private struct Fault: Decodable {
    let code: Int
    let message: String
}

private struct Envelope<R: Decodable>: Decodable {
    let result: R?
    let error: Fault?
}

private struct EsResult: Decodable {
    let socPct: Double
    let ongridW: Double
    let offgridW: Double
    let ratedWh: Double

    enum CodingKeys: String, CodingKey {
        case socPct = "bat_soc"
        case ongridW = "ongrid_power"
        case offgridW = "offgrid_power"
        case ratedWh = "bat_cap"
    }
}
