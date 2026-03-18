# Decepta AI - Veri Seti Araştırması

E-ticaret sahte yorum tespiti için kullanılabilecek potansiyel veri setleri ve değerlendirmeleri:

## 1. Amazon Customer Reviews Dataset
- **Kaynak:** AWS / Kaggle
- **Boyut:** 130+ Milyon yorum
- **Dil:** Çok dilli (Ağırlıklı İngilizce)
- **Durum:** Gerçek dünya verisi, ancak "sahte" etiketleri eksik olabilir. Unsupervised learning (Graph DB) testleri için kullanılabilir.

## 2. Yelp Dinings and Reviews Dataset
- **Kaynak:** Yelp Open Dataset
- **Özellikler:** Yelp'in filtrelediği (önerilmeyen/sahte muhtemel) yorumları içerir.
- **Değerlendirme:** Doğal NLP ve anomaly detection modelleri eğitmek için etiketli veri arayanlar için altın standart.

## 3. Deceptive Opinion Spam Corpus (Ott et al.)
- **Kaynak:** Kaggle / Academic Research
- **İçerik:** Otel yorumları (Gerçek vs. Amazon Mechanical Turk ile yazdırılmış sahte yorumlar).
- **Değerlendirme:** Linguistic kalıpları ve abartılı övgüleri (NLP) yakalamak için model fine-tuning aşamasında çok değerli.

## 4. Türkçe E-Ticaret Yorumları
- **Kaynak:** Kaggle (Çeşitli Hepsiburada/Trendyol kazınmış veri setleri)
- **Durum:** Türkçe modelleme için gerekli. Bot tarafından üretilmiş sahte verileri sentetik olarak (ChatGPT/LLM ile) üretip mevcut veri setine enjekte ederek kendi hibrit eğitim setimizi oluşturabiliriz.

---

### 🎯 Karar ve Yol Haritası
1. **Model Eğitimi (NLP):** Başlangıçta Türkçe modeller için Trendyol/Hepsiburada veri setlerini kullanıp, sentiment analizi yapacağız.
2. **Sahtekarlık Tespiti (Graph + Zaman):** Modelimizi "Deceptive Opinion Spam" mantığıyla eğiteceğiz. Türkçe sahte yorum setini sentetik olarak genişleteceğiz.
