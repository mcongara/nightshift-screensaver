import Foundation

// Observe system-wide lifecycle before a screensaver view is loaded. Modern
// macOS sometimes renders a thumbnail with isPreview == false, so a view alone
// cannot reliably decide whether the actual screen saver is active.
var active = false
var lastEvent = "monitorStarted"
let config = URLSessionConfiguration.ephemeral
config.timeoutIntervalForRequest = 2
config.connectionProxyDictionary = [:]
let client = URLSession(configuration: config)
func report() {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:47831/lifecycle")!)
    request.httpMethod = "POST"
    request.setValue("monitor-v1", forHTTPHeaderField: "X-NightShift")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["active": active, "event": lastEvent])
    client.dataTask(with: request).resume()
}
let center = DistributedNotificationCenter.default()
var observers: [NSObjectProtocol] = []
for name in ["com.apple.screensaver.willstart", "com.apple.screensaver.didstart",
             "com.apple.screensaver.willstop", "com.apple.screensaver.didstop", "com.apple.screenIsUnlocked"] {
    observers.append(center.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { _ in
        active = name.hasSuffix("willstart") || name.hasSuffix("didstart")
        lastEvent = name
        report()
    })
}
let timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in report() }
report()
RunLoop.main.run()
