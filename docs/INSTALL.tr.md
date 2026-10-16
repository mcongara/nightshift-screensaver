# Night Shift · Claude Code ekran koruyucu

Loş bir ekran, Claude Code sessionlarının son durumları ve gerçek screensaver
açıkken isteğe bağlı otomatik uyku koruması. Session varken “Vardiya.”,
session yokken yalnızca “Night Shift”, “Bekliyor.” ve saat görünür.

## Gerekenler

- Apple Silicon (M1/M2/M3/M4/M5 veya sonraki M serisi) Mac.
- macOS 15 veya üstü. Bu deneme sürümü macOS 26 üzerinde test edildi.
- Python 3.9 veya üstü ve yerel Claude Code. Python için python.org adresi
  veya mevcut Homebrew kurulumun kullanılabilir. Xcode ile derleme gerekmez.

## Kurulum

1. ZIP dosyasını tamamen aç. Dosyaları klasörün içinden çalıştır.
2. Kur.command dosyasına çift tıkla. Terminal kurulum sonucunu gösterir.
3. Sistem Ayarları → Duvar Kâğıdı → Ekran Koruyucu bölümünde Night Shift'i seç.
   Other / Diğer altında Show All / Tümünü Göster'e basman gerekebilir.
4. Claude Code sessionlarını yeniden aç. Kurulumdan önceki sessionların
   durumu geriye dönük aktarılmaz.
5. Otomatik başlama süresi veya Sıcak Köşe ayarla. Never seçiliyse otomatik başlamaz.

Kurulum kullanıcıya özeldir; sudo veya yönetici şifresi istemez. Claude'un mevcut
ayarlarını yedekler ve diğer hook'ları koruyarak kendi hook'larını ekler. Aynı
kurulumu tekrar çalıştırmak hook'ları çoğaltmaz.
TR ve EN sürümleri birbirinin yerine kurulur; aynı ayarları ve yerel verileri kullanır.

## Ayarlar ve kullanım

Options / Seçenekler: görüntü parlaklığı, saati gösterme, proje adlarını gizleme
ve uyanık tutma. macOS Tahoe bazen paneli gecikmeli açıyor; Sistem Ayarları'nı
kapatıp yeniden açmak gerekebilir. Ayarlar yerel köprü çalışırken kaydedilir.

Uyanık tutma seçiliyken gerçek screensaver otomatik ekran ve sistem uykusunu
engeller; çıkınca bırakır. Küçük önizleme tek başına uyku engeli açmaz. Bu özellik
kapak kapatmayı veya elle Uyku seçmeyi engellemez. Fiziksel ekran parlaklığını ve
macOS kilit/parola ayarlarını değiştirmez.

Session ismi, araç türü ve son hook zamanı gösterilir. Prompta, komut içeriğine
ve konuşma metnine erişilmez. 15 dakika sinyal gelmezse durum bilinmiyor olarak
gösterilir; sessiz uzun işlemler de bu duruma düşebilir. 3 saat yeni sinyal
gelmezse session listeden gizlenir.

## Kaldırma

Kaldir.command dosyasına çift tıkla. Screensaver, yardımcı süreçler ve yalnızca
Night Shift'in Claude hook'ları kaldırılır. Ayar yedekleri ve yerel veriler kalır.

## Deneme sürümü hakkında

Bu paket yerel denemeler için ad-hoc imzalıdır; Developer ID imzası ve Apple
notarizasyonu yoktur. İnternetten veya mesajlaşma uygulamasından indirildiğinde
macOS güvenlik kontrolü çalıştırmayı engelleyebilir. Paket güvenlik ayarlarını
değiştirmez veya bu kontrolleri kaldırmaz. Böyle bir sorun çıkarsa gönderen kişiye
hata mesajını bildir; geniş dağıtım için imzalı sürüm gerekir.

Pakette kişisel Claude ayarları, hesap bilgileri ve session verileri bulunmaz.
Yardımcı yalnızca 127.0.0.1:47831 üzerinde çalışır; yeni bir API anahtarı gerekmez.
