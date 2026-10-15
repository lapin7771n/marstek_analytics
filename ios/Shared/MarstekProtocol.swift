import Foundation

struct EsStatus: Equatable {
    let socPct: Int
    let ongridW: Double
    let offgridW: Double
    let ratedWh: Double
}

struct DeviceInfo: Equatable, Sendable {
    let model: String
    let mac: String?
    var firmware: Int? = nil
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

    static let venusRatedWh = 5120.0

    static func esStatus(_ data: Data) throws -> EsStatus {
        let result = try decode(EsResult.self, data)
        let rated = result.ratedWh ?? 0
        // A silent battery management system reports bat_cap 0, then bat_soc 0.
        guard rated > 0 || result.socPct > 0 else { throw DeviceError.badReply("Reply has bat_cap \(rated)") }
        return EsStatus(
            socPct: Int(result.socPct.rounded()), ongridW: result.ongridW, offgridW: result.offgridW ?? 0,
            ratedWh: rated > 0 ? rated : venusRatedWh
        )
    }

    // ver is an integer, a float like 150.9, a string like "148.3", or 1476 for 147.6.
    static func firmware(_ ver: Double?) -> Int? {
        guard let ver, ver >= 0, ver < 10_000 else { return nil }
        let whole = Int(ver)
        return (1000...1999).contains(whole) ? whole / 10 : whole
    }

    static func deviceRequest(id: Int) -> Data {
        Data(#"{"id":\#(id),"method":"Marstek.GetDevice","params":{"ble_mac":"0"}}"#.utf8)
    }

    static func device(_ data: Data) throws -> DeviceInfo {
        let result = try decode(DeviceResult.self, data)
        let mac = [result.wifiMac, result.bleMac].compactMap { $0 }.first { !$0.isEmpty }
        return DeviceInfo(model: result.device ?? "Marstek", mac: mac, firmware: firmware(result.ver))
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
    let offgridW: Double?
    let ratedWh: Double?

    enum CodingKeys: String, CodingKey {
        case socPct = "bat_soc"
        case ongridW = "ongrid_power"
        case offgridW = "offgrid_power"
        case ratedWh = "bat_cap"
    }
}

private struct DeviceResult: Decodable {
    let device: String?
    let wifiMac: String?
    let bleMac: String?
    let ver: Double?

    enum CodingKeys: String, CodingKey {
        case device, ver
        case wifiMac = "wifi_mac"
        case bleMac = "ble_mac"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        device = try values.decodeIfPresent(String.self, forKey: .device)
        wifiMac = try values.decodeIfPresent(String.self, forKey: .wifiMac)
        bleMac = try values.decodeIfPresent(String.self, forKey: .bleMac)
        if let number = try? values.decode(Double.self, forKey: .ver) {
            ver = number
        } else if let text = try? values.decode(String.self, forKey: .ver) {
            ver = Double(text.prefix { $0.isASCII && $0.isNumber })
        } else {
            ver = nil
        }
    }
}
