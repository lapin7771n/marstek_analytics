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

    func reading(at time: Date = .now) async throws -> Reading {
        let es = try MarstekProtocol.esStatus(await call("ES.GetStatus"))
        try await Task.sleep(for: gap)
        let bat = try MarstekProtocol.batStatus(await call("Bat.GetStatus"))
        return Reading(time: time, es: es, bat: bat)
    }

    func call(_ method: String) async throws -> Data {
        let id = MarstekProtocol.newId()
        do {
            return try await exchange(MarstekProtocol.request(id: id, method: method), id: id)
        } catch DeviceError.timeout {
            try await Task.sleep(for: gap)
            return try await exchange(MarstekProtocol.request(id: id + 1, method: method), id: id + 1)
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
