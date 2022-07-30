import CollectionsBenchmark
import Foundation
import struct _Concurrency.Task

let langs = [
    // These are twice as likely
    "go", "go",
    "kt", "kt",
    "py", "py",
    "swift", "swift",
    "ts", "ts",
    // as these
    "c", "c#", "java", "js", "lisp", "elm", "rb", "scala"
]

let urlSessionCfg = URLSessionConfiguration.ephemeral
urlSessionCfg.httpShouldUsePipelining = true
let urlSession = URLSession(configuration: urlSessionCfg)

class CountDownDelegate: NSObject, URLSessionWebSocketDelegate {
    let count: Int
    let completed: DispatchSemaphore
    let connected: DispatchSemaphore
    var done: Bool = false

    init(count: Int, completed: DispatchSemaphore, connected: DispatchSemaphore) {
        self.count = count
        self.completed = completed
        self.connected = connected
    }

    private func receiveMessages(_ count: Int, _ webSocketTask: URLSessionWebSocketTask) {
        webSocketTask.receive { [unowned self] result in
            switch (result) {
            case .success(_):
                if count <= 0 {
                    self.done = true
                    webSocketTask.cancel(with: .normalClosure, reason: nil)
                    self.completed.signal()
                } else {
                    self.receiveMessages(count - 1, webSocketTask)
                }
            case .failure(let err):
                webSocketTask.cancel()
                fatalError("received websocket failure message: \(err)")
            }
        }
    }

    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        receiveMessages(self.count, webSocketTask)
        connected.signal()
    }

    // Handles server initiated close (should never happen)
    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?
    ) {
        if !self.done {
            webSocketTask.cancel(with: .abnormalClosure, reason: nil)
            fatalError("server initiated websocket closure")
        }
    }
}

func registerWebSocketListener(expecting count: Int) throws -> DispatchSemaphore {
    guard
        let url = URL(string: "ws://localhost:8973/event/language-poll")
    else {
        throw NSError()
    }
    let completed = DispatchSemaphore(value: 0)
    let connected = DispatchSemaphore(value: 0)
    let urlSession: URLSession = URLSession(
        configuration: urlSessionCfg,
        delegate: CountDownDelegate(count: count, completed: completed, connected: connected),
        delegateQueue: OperationQueue()
    )
    let webSocketTask = urlSession.webSocketTask(with: url)
    webSocketTask.resume()
    connected.wait()

    return completed
}

func resetService() async throws {
    guard
        let url = URL(string: "http://localhost:8973/reset")
    else {
        throw NSError()
    }
    _ = try await urlSession.data(for: URLRequest(url: url))

}

func postRandomChat(senders: Int) async throws {
    guard
        let baseUrl = URL(string: "http://localhost:8973/chat"),
        var urlComps = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false)
    else {
        throw NSError()
    }
    urlComps.queryItems = [
        URLQueryItem(name: "route", value: "\(Int.random(in: 0..<senders)) to Everyone"),
        URLQueryItem(name: "text", value: langs.randomElement())
    ]

    guard let url = urlComps.url else {
        throw NSError()
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"

    _ = try await urlSession.data(for: req)
}

func postRandomChat(count: Int, concurrency: Int) {
    let semaphore = DispatchSemaphore(value: 0)
    let senders = count / 4
    let perThreadCount = count / concurrency

    for _ in 0..<concurrency {
        Task {
            for _ in 0..<perThreadCount {
                try await postRandomChat(senders: senders)
            }
            semaphore.signal()
        }
    }

    for _ in 0..<concurrency {
        semaphore.wait()
    }
}

func postRandomChatAndAwaitReception(count: Int, listenerCompletions: [DispatchSemaphore]) {
    postRandomChat(count: count, concurrency: 8)

    for completion in listenerCompletions {
        completion.wait()
    }
}

var benchmark = Benchmark(title: "Presentation Service")

benchmark.add(
    title: "Post Chat Event and Receive Poll Results",
    input: Int.self
) { input in
    return { timer in
        Task { try await resetService() }

        let requests: Int = 2048
        let listenerCompletions: [DispatchSemaphore] =
            try! (1...(input / 2048)).map { _ in
                try registerWebSocketListener(expecting: requests)
            }
        timer.measure {
            blackHole(
                postRandomChatAndAwaitReception(
                    count: requests,
                    listenerCompletions: listenerCompletions
                )
            )
        }
    }
}

benchmark.main()
