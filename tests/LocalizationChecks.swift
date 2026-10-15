import Foundation

let detailCases = [
    "Session açıldı": "Session started",
    "Session hazır": "Session ready",
    "Düşünüyor": "Thinking",
    "Yanıt tamamlandı": "Response complete",
    "Yanıt hata ile durdu": "Response stopped with an error",
    "İzin bekliyor": "Waiting for approval",
    "Yanıtını bekliyor": "Waiting for your response",
    "Yeni sinyal yok · son durum bilinmiyor": "No recent signal · current status unknown",
    "Bash çalışıyor": "Bash is running",
    "Edit için izin bekliyor": "Waiting for approval for Edit",
    "Read tamamlandı": "Read completed",
    "Bash hata verdi · devam ediyor": "Bash failed · continuing",
    "Araç çalışıyor": "Tool is running",
    "custom_tool": "custom_tool"
]
for (tr, en) in detailCases {
    precondition(localizedDetail(tr) == (Language.english ? en : tr), "Bad detail translation: \(tr)")
}
precondition(localized("Vardiya.", "Shift.") == (Language.english ? "Shift." : "Vardiya."))
precondition(localized("Bekliyor.", "Idle.") == (Language.english ? "Idle." : "Bekliyor."))
print("Localization checks passed: \(Language.english ? "EN" : "TR")")
