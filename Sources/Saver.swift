import AppKit
import ScreenSaver

@objc(NightShiftView)
final class NightShiftView: ScreenSaverView {
    private let canvas = NightCanvas(frame: .zero)
    private let feed = StateFeed()
    private var lastPoll = Date.distantPast
    private var running = false
    private var panel: OptionsPanel?
    private var updateTimer: Timer?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)
        // Prime every new view even if Tahoe never calls startAnimation for it.
        feed.poll(canvas: canvas, awake: false)
        // Modern legacyScreenSaver hosts may retain views without calling
        // stopAnimation. Stop the feed on system lifecycle notifications too.
        if !isPreview {
            let center = DistributedNotificationCenter.default()
            for name in ["com.apple.screensaver.willstop", "com.apple.screensaver.didstop", "com.apple.screenIsUnlocked"] {
                center.addObserver(self, selector: #selector(suspendFeed), name: NSNotification.Name(name), object: nil)
            }
            center.addObserver(self, selector: #selector(resumeFeed),
                               name: NSNotification.Name("com.apple.screensaver.didstart"), object: nil)
        }
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit {
        updateTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            running = true
            startUpdates()
        } else {
            updateTimer?.invalidate()
            updateTimer = nil
            feed.cancel()
        }
    }

    private func startUpdates() {
        updateTimer?.invalidate()
        lastPoll = .distantPast
        update()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    private func update() {
        guard running, window != nil else { return }
        canvas.now = Date()
        canvas.needsDisplay = true
        guard Date().timeIntervalSince(lastPoll) >= 2.5 else { return }
        lastPoll = Date()
        // Fetch data even when the host reports an occluded window during the
        // lock transition. Wake eligibility is independently gated by the bridge.
        feed.poll(canvas: canvas, awake: !isPreview && window?.isVisible == true)
    }

    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        if panel == nil {
            panel = OptionsPanel()
            panel?.onSave = { [weak self] in
                guard let self = self else { return }
                self.feed.poll(canvas: self.canvas, awake: false)
            }
        }
        panel?.reload()
        return panel?.window
    }

    @objc private func suspendFeed(_ notification: Notification) {
        running = false
        updateTimer?.invalidate()
        updateTimer = nil
        feed.cancel()
    }
    @objc private func resumeFeed(_ notification: Notification) {
        running = true
        startUpdates()
    }

    override func startAnimation() {
        super.startAnimation()
        running = true
        startUpdates()
    }
    override func stopAnimation() {
        running = false
        updateTimer?.invalidate()
        updateTimer = nil
        feed.cancel()
        super.stopAnimation()
    }
    override func animateOneFrame() {
        update()
    }
}
