import AppKit
import ScreenSaver

final class OptionsPanel: NSObject {
    let window: NSWindow
    private let brightness = NSSlider(value: 0.55, minValue: 0.15, maxValue: 1, target: nil, action: nil)
    private let clock = NSButton(checkboxWithTitle: localized("Saati göster", "Show clock"), target: nil, action: nil)
    private let privacy = NSButton(checkboxWithTitle: localized("Proje adlarını gizle", "Hide project names"), target: nil, action: nil)
    private let awake = NSButton(checkboxWithTitle: localized("Screensaver açıkken Mac’i uyanık tut", "Keep Mac awake while the screensaver is active"), target: nil, action: nil)
    private let errorLabel = NSTextField(labelWithString: "")
    private var saveButton: NSButton!
    private var edited = false
    private var loadGeneration = 0
    private let client: URLSession
    var onSave: (() -> Void)?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 366),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Night Shift"
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 4
        config.connectionProxyDictionary = [:]
        client = URLSession(configuration: config)
        super.init()
        let content = window.contentView!
        func label(_ title: String, _ rect: NSRect, size: CGFloat = 13) {
            let field = NSTextField(labelWithString: title)
            field.frame = rect
            field.font = NSFont.systemFont(ofSize: size)
            content.addSubview(field)
        }
        label(localized("Vardiya, senin ayarlarınla.", "Your shift, your settings."), NSRect(x: 24, y: 310, width: 390, height: 28), size: 20)
        label(localized("Görüntü parlaklığı", "Text brightness"), NSRect(x: 24, y: 276, width: 200, height: 20))
        brightness.frame = NSRect(x: 24, y: 244, width: 392, height: 24)
        brightness.target = self
        brightness.action = #selector(markEdited)
        brightness.setAccessibilityLabel(localized("Görüntü parlaklığı", "Text brightness"))
        content.addSubview(brightness)
        label(localized("Loş", "Dim"), NSRect(x: 24, y: 221, width: 100, height: 18), size: 11)
        label(localized("Daha görünür", "Brighter"), NSRect(x: 320, y: 221, width: 100, height: 18), size: 11)
        for (button, y) in [(clock, 187.0), (privacy, 153.0), (awake, 119.0)] {
            button.frame = NSRect(x: 24, y: y, width: 392, height: 24)
            button.target = self
            button.action = #selector(markEdited)
            content.addSubview(button)
        }
        label(localized("Ekranın fiziksel parlaklığını ve kilit ayarlarını değiştirmez.", "Does not change display brightness or lock settings."),
              NSRect(x: 24, y: 91, width: 400, height: 18), size: 11)
        errorLabel.frame = NSRect(x: 24, y: 61, width: 392, height: 20)
        errorLabel.font = NSFont.systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        content.addSubview(errorLabel)
        let cancel = NSButton(title: localized("Vazgeç", "Cancel"), target: self, action: #selector(cancelPanel))
        cancel.frame = NSRect(x: 225, y: 16, width: 88, height: 30)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        content.addSubview(cancel)
        saveButton = NSButton(title: localized("Kaydet", "Save"), target: self, action: #selector(savePanel))
        saveButton.frame = NSRect(x: 325, y: 16, width: 88, height: 30)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        content.addSubview(saveButton)
    }

    func reload() {
        edited = false
        errorLabel.stringValue = ""
        saveButton.isEnabled = true
        loadGeneration += 1
        let generation = loadGeneration
        let defaults = ScreenSaverDefaults(forModuleWithName: "local.nightshift.saver")
        defaults?.register(defaults: ["brightness": 0.55, "showClock": true, "hideProjects": false, "keepAwake": true])
        apply(SaverOptions(brightness: defaults?.double(forKey: "brightness") ?? 0.55,
                           showClock: defaults?.bool(forKey: "showClock") ?? true,
                           hideProjects: defaults?.bool(forKey: "hideProjects") ?? false,
                           keepAwake: defaults?.bool(forKey: "keepAwake") ?? true))
        client.dataTask(with: URL(string: "http://127.0.0.1:47831/preferences")!) { [weak self] data, _, _ in
            guard let data = data, let options = try? JSONDecoder().decode(SaverOptions.self, from: data) else { return }
            DispatchQueue.main.async {
                guard let self = self, self.loadGeneration == generation, !self.edited else { return }
                self.apply(options)
            }
        }.resume()
    }
    private func apply(_ options: SaverOptions) {
        brightness.doubleValue = options.brightness
        clock.state = options.showClock ? .on : .off
        privacy.state = options.hideProjects ? .on : .off
        awake.state = options.keepAwake ? .on : .off
    }
    @objc private func markEdited(_ sender: Any?) { edited = true }
    private func dismiss() {
        loadGeneration += 1
        if let parent = window.sheetParent { parent.endSheet(window) }
        window.orderOut(nil)
    }
    @objc private func cancelPanel() { dismiss() }
    @objc private func savePanel() {
        edited = true
        saveButton.isEnabled = false
        let options = SaverOptions(brightness: brightness.doubleValue, showClock: clock.state == .on,
                                   hideProjects: privacy.state == .on, keepAwake: awake.state == .on)
        let generation = loadGeneration
        var request = URLRequest(url: URL(string: "http://127.0.0.1:47831/preferences")!)
        request.httpMethod = "POST"
        request.setValue("saver-v1", forHTTPHeaderField: "X-NightShift")
        request.httpBody = try? JSONEncoder().encode(options)
        client.dataTask(with: request) { [weak self] _, response, _ in
            DispatchQueue.main.async {
                guard let self = self, self.loadGeneration == generation else { return }
                self.saveButton.isEnabled = true
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    self.errorLabel.stringValue = localized("Yerel köprüye ulaşılamadı. Tekrar dene.", "Cannot reach the local bridge. Try again.")
                    return
                }
                if let defaults = ScreenSaverDefaults(forModuleWithName: "local.nightshift.saver") {
                    defaults.set(options.brightness, forKey: "brightness")
                    defaults.set(options.showClock, forKey: "showClock")
                    defaults.set(options.hideProjects, forKey: "hideProjects")
                    defaults.set(options.keepAwake, forKey: "keepAwake")
                    defaults.synchronize()
                }
                self.onSave?()
                self.dismiss()
            }
        }.resume()
    }
}
