# UI Tel Kafes (Wireframe) Tasarımı

Proje iki ana hedef kitleye B2B ve B2C formatında hitap ettiği için arayüzler birbirinden bağımsız felsefede geliştirilecektir.

## 1. Decepta-AI-Mobile (Flutter B2C)

Tüketiciler içindir. **Minimal, çok hızlı ve sonucun hemen algılanmasını sağlayan** "Hap bilgi" odaklı bir yapıya sahiptir.

### Ekran 1: Karşılama ve Link Arama (Home Screen)
- **Başlık:** "Sahte Yorumlara Aldanmayın, Gerçek Skoru Öğrenin!"
- **Girdi Alanı:** Ekranın ortasında büyük bir URL yapıştırma çubuğu. (Örn: `https://www.trendyol.com/...`)
- **Aksiyon:** [ 🔍 Analiz Et ] büyük butonu.
- **Alt Bölüm:** "Son İncelediklerim" adlı yatay kayan bir geçmiş/keşfet alanı.

### Ekran 2: Yükleniyor (Loading state)
- Sistem, backend'e linki attıktan sonra animasyonlu yükleme:
  - *Adım 1:* "Yorumlar toplanıyor..."
  - *Adım 2:* "Yapay zeka dili analiz ediyor..."
  - *Adım 3:* "Graph DB bot ağlarını arıyor..."

### Ekran 3: Sonuç Raporu (Result Screen)
- **Arka Plan:** Duruma göre Kırmızı (Çok Bot var), Sarı (Şüpheli Yorumlar) veya Yeşil (Temiz).
- **Merkez (Puan Kartı):** 
  - "E-Ticaret Sitesi Puanı: 4.8 / 5.0" (Üstünü çizen ince çizgi)
  - **"Decepta Gerçek Güven Skoru: 2.3 / 5.0"** (Devasa Font)
- **Alt Sekmeler (Accordion / Kutu):**
  - **Neden Şüphelendik?** "Bu ürün yorumlarında **%60** oranında bot ağı aktivitesi gözlemledik."
  - **En Çok Tekrar Eden Şüpheli Kelimeler:** "Kargosu uçak gibi", "mükemmel sorunsuz mükemmel"

---

## 2. Decepta-AI-Web (React / Next.js B2B Panel)

Veri bilimciler, marka temsilcileri ve kriz yöneticileri içindir. **Bol miktarda grafik, D3.js ağ görselleştirmesi ve veri yoğun** (Data-Rich) bir ekrandır.

### Ekran 1: Dashboard (Yönetim Paneli)
- Üst Menü: `Genel Bakış` | `Rakipler` | `Uyarı/Alarmlar`
- Özet Kartları: Bugün taratılan ürün sayısı, engellenen/tespit edilen bot sayısı.
- Yeni Ürün Analiz Modülü: URL girdisi ve parametreler (Örn: Sadece son 3 ayı tara).

### Ekran 2: Detaylı Analitik (Product Report View)
- **Üst Banner:** Ürün Adı, Toplam Yorum, NLP Skor Özeti.
- **Sol Sütun (Zaman Serisi):**
  - Bir Çizgi Grafiği (Line Chart). X ekseni Tarih, Y ekseni Yorum Sayısı.
  - "15 Haziran'da Anormal Yükseliş: 2 saat içinde 350 tane 5 yıldızlı yorum gelmiş" baloncuğu (Spike Detection).
- **Sağ Sütun (NLP Sınıflandırması):**
  - Pozitif (Organik) / Negatif (Organik) / Pozitif (Bot/Sahte) olarak 3'e bölünmüş Donut Chart (Halka grafiği).
- **Alt Sütun (Devasa Ağ Grafiği - Neo4j):**
  - Interactive D3.js veya vis.js haritası.
  - Kullanıcı ortadaki ürün topuna mouse ile yaklaşabilir. Etrafında gruplanmış (aynı gün hesap açan kişiler vb.) kümelerin kırmızı renkli toplar olarak görülmesi ve detayına inilmesi.
