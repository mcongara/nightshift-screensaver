import Foundation

// Language is selected at build time; both editions share the same bridge protocol.
enum Language {
    #if ENGLISH
    static let english = true
    #else
    static let english = false
    #endif
}

func localized(_ turkish: String, _ english: String) -> String {
    Language.english ? english : turkish
}

func localizedDetail(_ value: String) -> String {
    guard Language.english else { return value }
    let phrases = [
        "Session açıldı": "Session started",
        "Session hazır": "Session ready",
        "Düşünüyor": "Thinking",
        "Yanıt tamamlandı": "Response complete",
        "Yanıt hata ile durdu": "Response stopped with an error",
        "İzin bekliyor": "Waiting for approval",
        "Yanıtını bekliyor": "Waiting for your response",
        "Yeni sinyal yok · son durum bilinmiyor": "No recent signal · current status unknown"
    ]
    if let translated = phrases[value] { return translated }
    // Translate only protocol suffixes, preserving tool names verbatim.
    for (suffix, translated) in [
        (" için izin bekliyor", "Waiting for approval for "),
        (" hata verdi · devam ediyor", " failed · continuing"),
        (" çalışıyor", " is running"),
        (" tamamlandı", " completed")
    ] {
        if value.hasSuffix(suffix) {
            let tool = String(value.dropLast(suffix.count))
            let name = tool == "Araç" ? "Tool" : tool
            return suffix == " için izin bekliyor" ? translated + name : name + translated
        }
    }
    return value
}
