import Foundation
import Network

enum DeviceError: Error, Equatable {
    case timeout
    case blocked
    case network(String)
    case badReply(String)

    static func from(_ error: NWError, path: NWPath?) -> DeviceError {
        if path?.unsatisfiedReason == .localNetworkDenied { return .blocked }
        return .network(error.debugDescription)
    }
}

struct MarstekClient {
    let host: String
    let port: UInt16
    var timeout: TimeInterval = 2
    var gap: Duration = .seconds(1)
    var retry = true
    var trace: (Date, String) -> Void = { _, _ in }

    func reading(at time: Date = .now) async throws -> Reading {
        Reading(time: time, es: try MarstekProtocol.esStatus(await call("ES.GetStatus")))
    }

    func device() async throws -> DeviceInfo {
        let id = MarstekProtocol.newId()
        return try MarstekProtocol.device(await exchange(MarstekProtocol.deviceRequest(id: id), id: id))
    }

    func call(_ method: String) async throws -> Data {
        let id = MarstekProtocol.newId()
        do {
            return try await attempt(method, id: id)
        } catch DeviceError.timeout where retry {
            try await Task.sleep(for: gap)
            return try await attempt(method, id: id + 1)
        }
    }

    private func attempt(_ method: String, id: Int) async throws -> Data {
        let start = Date.now
        let target = "\(method) to \(host):\(port)"
        do {
            let data = try await exchange(MarstekProtocol.request(id: id, method: method), id: id)
            trace(start, "\(target): reply in \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
            return data
        } catch {
            trace(start, "\(target): \(error) after \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
            throw error
        }
    }

    private func exchange(_ request: Data, id: Int) async throws -> Data {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw DeviceError.network("Bad port") }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .udp)
        let queue = DispatchQueue(label: "marstek.udp")
        let timeout = timeout
        defer { connection.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation)
            let fail = { (error: NWError) in once.resume(.failure(DeviceError.from(error, path: connection.currentPath))) }

            connection.stateUpdateHandler = { state in
                switch state {
                case .waiting(let error), .failed(let error): fail(error)
                default: break
                }
            }

            func listen() {
                connection.receiveMessage { data, _, _, error in
                    if let error { fail(error); return }
                    guard let data, (try? MarstekProtocol.replyId(data)) == id else { listen(); return }
                    once.resume(.success(data))
                }
            }

            connection.start(queue: queue)
            connection.send(content: request, completion: .contentProcessed { error in
                if let error { fail(error) }
            })
            listen()
            queue.asyncAfter(deadline: .now() + timeout) { once.resume(.failure(DeviceError.timeout)) }
        }
    }
}
