<p align="center">
  <h1 align="center">📱 Decepta AI — Mobile App</h1>
  <p align="center">
    <strong>E-Ticaret Sahte Yorum ve Bot Ağı Tespit Platformu</strong>
  </p>
  <p align="center">
    <a href="#teknoloji-yığını">Tech Stack</a> •
    <a href="#mimari">Mimari</a> •
    <a href="#kurulum">Kurulum</a> •
    <a href="#yol-haritası">Yol Haritası</a>
  </p>
</p>

---

## 📋 Proje Hakkında

Decepta AI, e-ticaret platformlarındaki sahte yorumları ve organize bot ağlarını tespit eden yapay zekâ destekli bir analiz platformudur.

Bu repo, **son tüketiciler (B2C)** için tasarlanmış **Flutter Mobil Uygulamasını**, backend API'yi ve yapay zekâ modüllerini içerir. Tüketiciler, şüphelendikleri bir ürünün linkini uygulamaya yapıştırarak saniyeler içinde tarafsız bir "Güven Skoru" elde edebilirler.

### Temel Özellikler

| Özellik | Açıklama |
|:---|:---|
| 🔗 **Hızlı Analiz** | Trendyol, Amazon vb. e-ticaret ürün linki ile anında analiz |
| 🛡️ **Gerçek Güven Skoru** | Bot ve sahte yorumlardan arındırılmış organik kullanıcı puanı |
| 📊 **Şeffaflık** | Hangi yorumların neden şüpheli bulunduğuna dair kanıtlar (Örn: Abartılı övgü) |
| 🤖 **Yapay Zekâ Özü** | NLP (Doğal Dil İşleme) ve Graph DB ile çok katmanlı analiz |

---

## 🛠️ Teknoloji Yığını

| Katman | Teknoloji |
|:---|:---|
| **Yapay Zekâ** | Python, Scikit-learn, HuggingFace Transformers |
| **Backend** | FastAPI (Asenkron REST API) |
| **Veritabanı** | PostgreSQL + Neo4j (Graph DB) |
| **Frontend** | Flutter (iOS & Android Çapraz Platform) |
| **Veri Toplama** | Web Scraping Botları |

---

## 🏗️ Mimari

```
Decepta-AI-Mobile/
├── ai/                    # Yapay zekâ modülleri (Paylaşılan Core)
│   ├── src/
│   │   ├── preprocessing/ # Veri temizleme
│   │   ├── sentiment/     # Duygu analizi
│   │   └── graph_analysis/# Ağ analizi
│   ├── tests/
│   └── notebooks/
│
├── backend/               # FastAPI REST API
│   └── app/
│       ├── main.py
│       ├── routers/
│       ├── models/
│       └── services/
│
├── mobile/                # Flutter mobil uygulama
│   └── lib/
│       ├── screens/       # UI Ekranları
│       ├── widgets/       # Tekrar kullanılabilir bileşenler
│       └── services/      # API entegrasyonu
│
└── docs/                  # Proje dokümantasyonu
```

---

## 🚀 Kurulum

### Gereksinimler

- Python 3.11+
- Flutter SDK 3.19+
- PostgreSQL 15+
- Neo4j 5+

### AI & Backend Kurulumu

```bash
# AI bağımlılıklarını yükle
cd ai
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Backend'i başlat
cd ../backend
pip install -r requirements.txt
uvicorn app.main:app --reload
```

### Flutter Mobil Kurulumu

```bash
cd mobile
flutter pub get
flutter run
```

---

## 🗺️ Yol Haritası

| Hafta | Kapsam | Durum |
|:---:|:---|:---:|
| 1 | Proje kurulumu, veri araştırması, NLP metodoloji | ✅ |
| 2 | Veritabanı şemaları, Mobil wireframe | ⬜ |
| 3 | Veri ön işleme pipeline | ⬜ |
| 4 | HuggingFace duygu analizi | ⬜ |
| 5 | Neo4j entegrasyonu, graph algoritmaları | ⬜ |
| 6 | Web scraping servisi | ⬜ |
| 7 | FastAPI backend kurulumu | ⬜ |
| 8 | Flutter mobil arayüz kodlama | ⬜ |
| 10 | E2E testler ve tam akış | ⬜ |
| 11 | Cloud API deployment, MVP lansman | ⬜ |

---

## 📄 Lisans

Bu proje [MIT Lisansı](LICENSE) ile lisanslanmıştır.

---

<p align="center">
  <sub>Decepta AI © 2025 — Tarafsız ve güvenli alışveriş.</sub>
</p>
