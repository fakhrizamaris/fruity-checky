# Kredit

Orang BAIK adalah Proof of Concept. Model berjalan di iPhone, tanpa jaringan.

## Dataset

- **RipeNet 2.0** (alexcj10, [github.com/alexcj10/ripenet](https://github.com/alexcj10/ripenet)): pisang, mangga, jeruk, pepaya, nanas dengan kelas Unripe, Fresh, Rotten. Gambar dikumpulkan dengan scraping mesin pencari dan lisensi tiap gambar tidak jelas. Hanya untuk eksperimen PoC; ganti dengan foto sendiri sebelum dipublikasikan.
- **Banana Ripeness Classification Dataset** (versi model pisang sebelumnya): kelas unripe, ripe, overripe, rotten. Penulis: TODO. Link: TODO. Lisensi: TODO.

## Model

- **RipeNetV2** (default): model multi-task RipeNet V2 dari [github.com/alexcj10/ripenet](https://github.com/alexcj10/ripenet) (`saved_models/ripenet_v2_mtl.pth`): EfficientNet-B0 dengan kepala tahap kematangan, jenis buah, dan sisa hari. Dikonversi ke Core ML dengan ml/convert_ripenet.py tanpa dilatih ulang. Repo tersebut tidak mencantumkan lisensi; hanya untuk eksperimen PoC. Kepala sisa hari dilatih dari label sintetis, jadi tidak ditampilkan ke pengguna.

- **BananaRipeness, MangoRipeness, OrangeRipeness, PapayaRipeness, PineappleRipeness**: EfficientNet-B0 dari torchvision (bobot pretrained ImageNet), di-fine-tune per buah. Notebook: ml/train_ripeness.ipynb.

## Perubahan dari dataset asli

- Kelas RipeNet dipetakan ke label PoC: Unripe → mentah, Fresh → matang, Rotten → busuk. Kelas terlalu matang tidak ada di RipeNet.
- Gambar rusak, duplikat (termasuk yang hampir sama), dan gambar yang muncul di dua kelas dibuang, lalu dibagi 70/15/15 per buah.
- Gambar yang dicatat di ml/excluded_images.txt dibuang setelah review manual.

## Pengetahuan cek fisik

- Kalimat alasan dan langkah cek fisik adalah ringkasan awal dan masih perlu diverifikasi (TODO: UC Davis Postharvest Technology Center, [postharvest.ucdavis.edu](https://postharvest.ucdavis.edu)).
