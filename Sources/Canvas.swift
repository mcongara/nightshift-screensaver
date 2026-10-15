import AppKit
import Foundation

struct AgentSession: Decodable {
    let id: String
    let project: String
    let startedAt: Double
    let updatedAt: Double
    let status: String
    let detail: String
}
struct SaverOptions: Codable {
    var brightness = 0.55
    var showClock = true
    var hideProjects = false
    var keepAwake = true
}
struct BridgeState: Decodable {
    let sessions: [AgentSession]
    let awake: Bool?
    let preferences: SaverOptions?
}

// Near-black canvas, a warm signal and a quiet typographic session list.
enum Palette {
    static let background = NSColor(calibratedWhite: 0.008, alpha: 1)
    static let heading = NSColor(calibratedWhite: 0.38, alpha: 1)
    static let ink = NSColor(calibratedWhite: 0.29, alpha: 1)
    static let muted = NSColor(calibratedWhite: 0.19, alpha: 1)
    static let line = NSColor(calibratedWhite: 0.075, alpha: 1)
    static let signal = NSColor(calibratedRed: 0.48, green: 0.30, blue: 0.22, alpha: 1)
    static let quiet = NSColor(calibratedRed: 0.24, green: 0.32, blue: 0.28, alpha: 1)
}

final class NightCanvas: NSView {
    var agents: [AgentSession] = []
    var connected = false
    var attemptedConnection = false
    var demo = false
    var now = Date()
    var brightness = 0.55
    var showClock = true
    var hideProjects = false
    var wakeProtected = false

    override var isFlipped: Bool { true }

    private func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat,
                      size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular,
                      mono: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                        : NSFont.systemFont(ofSize: size, weight: weight)
        let scaled = color.usingColorSpace(.deviceRGB)!
        let multiplier = brightness / 0.55
        let ink = NSColor(calibratedRed: min(1, scaled.redComponent * multiplier),
                          green: min(1, scaled.greenComponent * multiplier),
                          blue: min(1, scaled.blueComponent * multiplier), alpha: 1)
        (value as NSString).draw(in: NSRect(x: x, y: y, width: max(0, width), height: size * 1.6),
            withAttributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.background.setFill()
        bounds.fill()
        let compact = bounds.width < 500 || bounds.height < 420
        let width = min(680, bounds.width - (compact ? 32 : 100))
        // Slowly shift the entire composition to reduce static pixel exposure.
        let t = now.timeIntervalSince1970 / 90
        let driftX: CGFloat = compact ? 0 : CGFloat(sin(t)) * 14
        let driftY: CGFloat = compact ? 0 : CGFloat(cos(t * 0.8)) * 12
        let x = (bounds.width - width) / 2 + driftX
        let maxRows = compact ? 2 : max(1, min(5, Int((bounds.height - 300) / 80)))
        let rows = Array(agents.prefix(maxRows))
        let resting = connected && agents.isEmpty
        let showSummary = !resting && (!connected || agents.count != 1)
        let omittedSpace: CGFloat = showSummary ? 0 : compact ? 20 : 40
        let contentHeight: CGFloat = resting ? (compact ? 112 : 160) : (compact ? 190 : 220 + CGFloat(max(1, rows.count)) * 78) - omittedSpace
        let top = max(16, (bounds.height - contentHeight) / 2) + driftY
        text("Night Shift", x: x, y: top, width: width,
             size: compact ? 9 : 11, color: Palette.muted, mono: true)
        text(resting ? localized("Bekliyor.", "Idle.") : localized("Vardiya.", "Shift."), x: x - 2, y: top + (compact ? 25 : 33), width: width,
             size: compact ? 28 : 52, color: Palette.heading, weight: .light)
        if resting {
            if showClock {
                let format = DateFormatter()
                format.dateFormat = "HH:mm"
                text(format.string(from: now), x: x, y: top + (compact ? 88 : 130), width: 90,
                     size: compact ? 11 : 12, color: Palette.muted, mono: true)
            }
            return
        }
        let working = agents.filter { $0.status == "working" }.count
        let waiting = agents.filter { ["approval", "input"].contains($0.status) }.count
        let summary: String
        if !connected { summary = attemptedConnection ? localized("Yerel bağlantı yenileniyor", "Reconnecting to the local bridge") : localized("Session durumları yükleniyor", "Loading sessions") }
        else if agents.isEmpty { summary = localized("Henüz session sinyali yok", "No session signal yet") }
        else if waiting > 0 { summary = localized("\(working) çalışıyor · \(waiting) seni bekliyor", "\(working) working · \(waiting) waiting for you") }
        else if working > 0 { summary = localized("\(working) session çalışıyor", "\(working) session(s) working") }
        else { summary = localized("\(agents.count) session", "\(agents.count) session(s)") }
        if showSummary {
            text(summary, x: x, y: top + (compact ? 68 : 103), width: width,
                 size: compact ? 11 : 16, color: Palette.ink)
        }
        var y = top + (compact ? 103 : 163) - omittedSpace
        if rows.isEmpty {
            text(connected ? localized("Yeni bir Claude Code sessionı açınca burada görünür.", "New Claude Code sessions appear here.")
                           : localized("Yerel köprü çalışınca durumlar burada görünür.", "Session status appears when the local bridge is running."),
                 x: x, y: y, width: width, size: compact ? 10 : 13, color: Palette.muted)
            y += compact ? 35 : 78
        }
        for (index, agent) in rows.enumerated() {
            Palette.line.setFill()
            NSRect(x: x, y: y, width: width, height: 1).fill()
            let waiting = ["approval", "input", "error"].contains(agent.status)
            (waiting ? Palette.signal : agent.status == "working" ? Palette.quiet : Palette.muted).setFill()
            let dot = NSRect(x: x, y: y + 21, width: 5, height: 5)
            NSBezierPath(ovalIn: dot).fill()
            text(hideProjects ? "Session \(index + 1)" : agent.project, x: x + 18, y: y + 14, width: width - 100,
                 size: compact ? 12 : 18, color: Palette.ink, weight: .medium)
            let age = max(0, Int(now.timeIntervalSince1970 - agent.updatedAt))
            let elapsed = age < 60 ? localized("az önce", "just now") : age < 3600 ? localized("\(age / 60) dk önce", "\(age / 60)m ago") : localized("\(age / 3600) sa önce", "\(age / 3600)h ago")
            if !compact {
                text(elapsed, x: x + width - 95, y: y + 17, width: 95,
                     size: 11, color: Palette.muted, mono: true)
            }
            text(localizedDetail(agent.detail), x: x + 18, y: y + (compact ? 34 : 43), width: width - 18,
                 size: compact ? 10 : 13, color: waiting ? Palette.signal : Palette.muted)
            y += compact ? 57 : 78
        }
        if !compact {
            if agents.count > rows.count {
                text(localized("+\(agents.count - rows.count) session daha", "+\(agents.count - rows.count) more session(s)"), x: x, y: y + 10,
                     width: width, size: 11, color: Palette.muted)
            }
            let format = DateFormatter()
            format.dateFormat = "HH:mm"
            if showClock {
                text(format.string(from: now), x: x, y: y + 50, width: 90,
                     size: 12, color: Palette.muted, mono: true)
            }
            text(demo ? localized("ÖRNEK VERİ · CANLI SESSION DEĞİL", "SAMPLE DATA · NOT LIVE SESSIONS") : wakeProtected ? localized("UYKU ENGELLENİYOR", "SLEEP PREVENTION ACTIVE") : localized("SON HOOK SİNYALLERİ", "LATEST HOOK SIGNALS"),
                 x: x + 100, y: y + 51, width: width - 100, size: 10,
                 color: Palette.muted, mono: true)
        }
    }
}

final class StateFeed {
    private let session: URLSession
    private var pending = false
    private var generation = 0
    private var stateTask: URLSessionDataTask?
    private var presenceTask: URLSessionDataTask?
    private var failureReported = false
    init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 3
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config)
    }
    func cancel() {
        generation += 1
        pending = false
        // Cancel only the tasks from this generation. Asynchronous getAllTasks
        // can race with resume and accidentally cancel the *new* request.
        stateTask?.cancel()
        presenceTask?.cancel()
        stateTask = nil
        presenceTask = nil
    }
    func poll(canvas: NightCanvas, awake: Bool) {
        guard !pending else { return }
        pending = true
        let current = generation
        let url = URL(string: "http://127.0.0.1:47831/state")!
        stateTask = session.dataTask(with: url) { [weak self, weak canvas] data, response, error in
            let state = data.flatMap { try? JSONDecoder().decode(BridgeState.self, from: $0) }
            DispatchQueue.main.async {
                guard let self = self, self.generation == current, let canvas = canvas else { return }
                self.pending = false
                canvas.attemptedConnection = true
                canvas.connected = (response as? HTTPURLResponse)?.statusCode == 200 && state != nil
                if canvas.connected {
                    canvas.agents = state?.sessions ?? []
                    self.failureReported = false
                } else if !self.failureReported {
                    let code = (error as NSError?)?.code ?? (response as? HTTPURLResponse)?.statusCode ?? 0
                    NSLog("NightShift state feed failed (code %ld, decoded %d)", code, state != nil ? 1 : 0)
                    self.failureReported = true
                }
                canvas.wakeProtected = canvas.connected && (state?.awake ?? false)
                if let preferences = state?.preferences {
                    canvas.brightness = preferences.brightness
                    canvas.showClock = preferences.showClock
                    canvas.hideProjects = preferences.hideProjects
                }
                canvas.now = Date()
                canvas.needsDisplay = true
            }
        }
        stateTask?.resume()
        if awake {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:47831/presence")!)
            request.httpMethod = "POST"
            request.setValue("saver-v1", forHTTPHeaderField: "X-NightShift")
            presenceTask = session.dataTask(with: request)
            presenceTask?.resume()
        }
    }
}
