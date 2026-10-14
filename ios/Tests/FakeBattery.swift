import Foundation
import Network
@testable import BatteryETA

struct FakeRequest: Decodable {
    let id: Int
    let method: String
}

final class FakeBattery: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake.battery")
    private let reply: (FakeRequest, Int) -> [String]
    private var attempts = 0

    private init(listener: NWListener, reply: @escaping (FakeRequest, Int) -> [String]) {
        self.listener = listener
        self.reply = reply
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    static func start(reply: @escaping (FakeRequest, Int) -> [String]) async throws -> FakeBattery {
        let fake = FakeBattery(listener: try NWListener(using: .udp, on: .any), reply: reply)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once(continuation)
            fake.listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(.success(()))
                case .failed(let error): once.resume(.failure(error))
                default: break
                }
            }
            fake.listener.newConnectionHandler = { connection in
                connection.start(queue: fake.queue)
                fake.listen(connection)
            }
            fake.listener.start(queue: fake.queue)
        }
        return fake
    }

    func stop() {
        listener.cancel()
    }

    private func listen(_ connection: NWConnection) {
        connection.receiveMessage { [self] data, _, _, error in
            guard error == nil, let data, let request = try? JSONDecoder().decode(FakeRequest.self, from: data) else { return }
            attempts += 1
            for text in reply(request, attempts) {
                connection.send(content: Data(text.utf8), completion: .idempotent)
            }
            listen(connection)
        }
    }
}
