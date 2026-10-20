# Orang BAIK: app iOS

> Salinan dari `PoC/CekBuah` (20 Okt 2026) dengan fitur belanja: pindai live satu per satu, foto rak dengan tap kotak untuk memilih/mengembalikan buah, dan keranjang. Bundle ID `com.orangbaik.poc`, jadi bisa terpasang berdampingan dengan Cek Buah (`com.cekbuah.poc`). Nama target dan modul di Xcode tetap `CekBuah`.

PoC Apple Developer Academy (tim "Orang BAIK"): menilai kematangan buah dari foto iPhone, sepenuhnya on-device,
lalu mengatur stok buah sebagai antrean (yang lebih cepat habis maju ke depan).
Training modelnya ada di repo terpisah: **cek-buah-ml**.

- SwiftUI + Observation, Core ML, Vision, AVFoundation, PhotosUI, SwiftData, UserNotifications.
- Tanpa library pihak ketiga, tanpa jaringan/akun/analytics (`PrivacyInfo.xcprivacy` disertakan).
- Xcode 27, iOS 27, Swift 6. Belum diuji di iPhone fisik.

## Menjalankan

1. Buka `CekBuah.xcodeproj`, pilih Team di Signing & Capabilities.
2. Pilih iPhone (iOS 27) lalu Run. Simulator tidak punya kamera; pakai "Pilih dari galeri".
3. Tes: ⌘U (Swift Testing).

Model default: `RipeNetV2.mlpackage` (satu model untuk semua buah, dari github.com/alexcj10/ripenet). Lima model per buah
(±7,8 MB per buah) tetap ada dan bisa dipilih di Mode penguji → "Model kematangan". Nama model tercatat di Log/CSV
(kolom `model`) supaya keduanya bisa dibandingkan di lapangan. Buah tanpa model berjalan dalam mode demo.

## Alur

Satu buah per foto, pengguna tidak memilih buah:

Beranda → **Pindai buah** (kamera dengan label langsung dari RipeNetV2, ±3 kali per detik) atau **Pilih dari galeri** →
kotak tengah foto → RipeNetV2 mengenali jenis buah (6 buah: pisang, mangga, jeruk, pepaya, nanas, apel); bila peluangnya
< 60% app bertanya "Apakah ini …?" dan pengguna bisa memilih buah lain → kematangan (label tampil bila peluang ≥ 50%,
selain itu "tidak yakin" dan diarahkan ke cek fisik) → perkiraan sisa hari sesuai label → stok (buah busuk tidak disimpan).

Deteksi banyak buah dan rencana YOLO ditunda: lihat `docs/rencana-yolo.md` di folder PoC.

```
CekBuah/
├── App/            Entry point, navigasi
├── Features/       Home, Camera, Result, PhysicalCheck, Stock, Log, Credits
├── Domain/         DecisionRules, ShelfLife, StockQueue, KnowledgeBase, FruitIdentity
├── Services/       Classifier (Core ML/mock), detektor buah, identifier, kamera, notifikasi
├── DesignSystem/   Tokens, StatusBadge, ResultCard, DetectionOverlay, IdentityNotice
└── Resources/      knowledge-base.json, Credits.md, PrivacyInfo, Models/
CekBuahTests/       Unit test
```

## Mode penguji

Menu ⋯ → "Mode penguji" (mati secara default): detail model, tombol "hasil sesuai?", Log + ekspor CSV, simulasi waktu,
notifikasi uji, dan ambang cek jenis buah. Pengguna biasa hanya melihat output inti.

## Keterbatasan

- Model dilatih pada RipeNet 2.0 (hasil scraping, lisensi tidak jelas); akurasi uji 67,7% (nanas) sampai 93,6% (pisang)
  terlalu optimis dan bukan hasil uji lapangan.
- Perkiraan sisa hari adalah tabel umum per tahap pada suhu ruang, bukan pengukuran.
- Detail dan sumber data: lihat `CekBuah/Resources/Credits.md` dan repo **cek-buah-ml**.
