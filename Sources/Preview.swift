import AppKit

let application = NSApplication.shared
let arguments = CommandLine.arguments
let demo = arguments.contains("--demo") || arguments.contains("--scenario")
let canvas = NightCanvas(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
canvas.demo = demo
if demo {
    canvas.connected = true
    let now = Date().timeIntervalSince1970
    canvas.agents = [
        AgentSession(id: "demo1", project: "agent-screensaver", startedAt: now - 920, updatedAt: now - 8,
                     status: "working", detail: "Bash çalışıyor"),
        AgentSession(id: "demo2", project: "storefront", startedAt: now - 600, updatedAt: now - 70,
                     status: "approval", detail: "Edit için izin bekliyor"),
        AgentSession(id: "demo3", project: "design-system", startedAt: now - 1900, updatedAt: now - 180,
                     status: "idle", detail: "Yanıt tamamlandı")
    ]
    if arguments.contains("--single") { canvas.agents = Array(canvas.agents.prefix(1)) }
}
// Explicit fixtures let reviewers capture every UI state without changing live sessions.
if let index = arguments.firstIndex(of: "--scenario"), index + 1 < arguments.count {
    let scenario = arguments[index + 1]
    let now = canvas.now.timeIntervalSince1970
    canvas.demo = true
    canvas.connected = true
    canvas.agents = []
    let fixtures: [String: (String, String)] = [
        "working": ("working", "Bash çalışıyor"),
        "approval": ("approval", "Edit için izin bekliyor"),
        "input": ("input", "Yanıtını bekliyor"),
        "idle": ("idle", "Yanıt tamamlandı"),
        "error": ("error", "Yanıt hata ile durdu"),
        "unknown": ("unknown", "Yeni sinyal yok · son durum bilinmiyor")
    ]
    if let fixture = fixtures[scenario] {
        canvas.agents = [AgentSession(id: "sample", project: "agent-screensaver",
            startedAt: now - 900, updatedAt: now - (scenario == "unknown" ? 960 : 20),
            status: fixture.0, detail: fixture.1)]
    } else if scenario == "loading" || scenario == "disconnected" {
        canvas.connected = false
        canvas.attemptedConnection = scenario == "disconnected"
    } else if scenario == "mixed" || scenario == "reconnecting" {
        canvas.agents = [
            AgentSession(id: "sample1", project: "agent-screensaver", startedAt: now - 900,
                         updatedAt: now - 8, status: "working", detail: "Bash çalışıyor"),
            AgentSession(id: "sample2", project: "storefront", startedAt: now - 600,
                         updatedAt: now - 70, status: "approval", detail: "Edit için izin bekliyor"),
            AgentSession(id: "sample3", project: "design-system", startedAt: now - 1900,
                         updatedAt: now - 180, status: "idle", detail: "Yanıt tamamlandı")
        ]
        if scenario == "reconnecting" {
            canvas.connected = false
            canvas.attemptedConnection = true
        }
    } else if scenario != "empty" {
        fputs("Unknown preview scenario: \(scenario)\n", stderr)
        exit(1)
    }
}
if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 900,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    canvas.displayIgnoringOpacity(canvas.bounds, in: NSGraphicsContext.current!)
    NSGraphicsContext.restoreGraphicsState()
    try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[index + 1]))
    exit(0)
}

class PreviewDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let feed = StateFeed()
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: canvas.bounds, styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.title = demo ? localized("Night Shift · örnek veri", "Night Shift · sample data") : localized("Night Shift · canlı önizleme", "Night Shift · live preview")
        window.contentView = canvas
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if !demo {
            feed.poll(canvas: canvas, awake: false)
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                self?.feed.poll(canvas: canvas, awake: false)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let delegate = PreviewDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
