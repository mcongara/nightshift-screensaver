import AppKit
import Foundation

final class MockProtocol: URLProtocol, @unchecked Sendable {
    struct Reply { let project: String?; let delay: Double }
    static var replies: [Reply] = []
    static var started = 0
    static let lock = NSLock()
    private let stateLock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let reply = Self.replies.removeFirst()
        Self.started += 1
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            stateLock.lock()
            defer { stateLock.unlock() }
            guard !stopped else { return }
            guard let project = reply.project else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let json: [String: Any] = ["sessions": [["id": "fixture", "project": project,
                "startedAt": 1, "updatedAt": 1, "status": "working", "detail": "Read çalışıyor"]], "awake": false]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: json))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }
}

func waitUntil(_ predicate: () -> Bool) {
    let limit = Date().addingTimeInterval(3)
    while !predicate() && Date() < limit {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(predicate(), "Feed did not reach expected state")
}
func enqueue(_ project: String?, delay: Double = 0.02) {
    MockProtocol.lock.lock()
    MockProtocol.replies.append(.init(project: project, delay: delay))
    MockProtocol.lock.unlock()
}
if CommandLine.arguments.contains("--live") {
    let feed = StateFeed()
    let canvas = NightCanvas(frame: .zero)
    feed.poll(canvas: canvas, awake: false)
    waitUntil { canvas.attemptedConnection }
    precondition(canvas.connected, "Native feed could not decode the live bridge response")
    print("Native live bridge read passed: \(canvas.agents.count) session(s), without a window or animation callback")
    exit(0)
}
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockProtocol.self]
let feed = StateFeed(configuration: config)
let canvas = NightCanvas(frame: .zero)

enqueue("first")
feed.poll(canvas: canvas, awake: false)
waitUntil { canvas.connected }
precondition(canvas.window == nil && canvas.agents.first?.project == "first")

enqueue(nil)
feed.poll(canvas: canvas, awake: false)
waitUntil { !canvas.connected }
precondition(canvas.agents.first?.project == "first", "Transient failures must retain last known state")

enqueue("cancelled", delay: 0.3)
enqueue("fresh")
feed.poll(canvas: canvas, awake: false)
waitUntil {
    MockProtocol.lock.lock()
    defer { MockProtocol.lock.unlock() }
    return MockProtocol.started == 3
}
feed.cancel()
feed.poll(canvas: canvas, awake: false)
waitUntil { canvas.connected && canvas.agents.first?.project == "fresh" }
RunLoop.main.run(until: Date().addingTimeInterval(0.35))
precondition(canvas.agents.first?.project == "fresh", "Old generation must not overwrite the new state")
print("Native feed regression checks passed: unattached first load, transient failure, cancel/resume race")
