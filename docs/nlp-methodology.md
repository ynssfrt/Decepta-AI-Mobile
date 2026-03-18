# Decepta AI - NLP ve Analiz Metodolojisi

Sahte yorumların ve organize e-ticaret bot ağlarının tespiti için 3 katmanlı (Multi-layered) bir siber analiz yöntemi kullanılacaktır.

## Katman 1: Doğal Dil İşleme (NLP)
Bu katman yorumun içeriğini (metni) inceleyerek dilbilimsel anormallikleri tespit eder.

- **Duygu Analizi (Sentiment):** HuggingFace `BERTurk` veya `mBERT` temelli bir model. Aşırı pozitifliği (Örn: "Hayatımda gördüğüm en mükemmel, kusursuz ve olağanüstü ürün!!") tespit etmek için kullanılacaktır.
- **Şablon Tespiti (Pattern Recognition):** Botların sıkça kullandığı kopyala-yapıştır yorum kalıplarının Tokenization ile benzerlik (Cosine Similarity vb.) metrikleriyle ölçülmesi.
- **Uzunluk ve Karmaşıklık:** Organik yorumlar genellikle dengeli bir uzunluğa ve doğal dilbilgisel hatalara sahip olur. Botlarda ise kusursuz veya aşırı kısa ("Çok iyi", "Harika") şablonlar sıktır.

## Katman 2: Zaman Serisi Analizi (Velocity)
Organize saldırıların ve botların doğası gereği zamansal yığılmalar yaşanır.

- **Spike Detection:** Spesifik bir ürünün normal yorum alma ritmi (örn: günde 3 yorum) aniden fırlarsa (1 saatte 50 yorum) sistem alarm üretir.
- **Hesap Yaşı / Yorum Hızı:** Yeni açılmış bir hesabın 1 gün içinde farklı ürünlere yüzlerce 5 yıldızlı yorum atması, şüpheli faaliyet ("Velocity Risk") puanını artırır.

## Katman 3: Ağ ve İlişki Analizi (Graph DB - Neo4j)
Tekil yorumlar normal görünse bile, büyük resmi görmek için ilişkisel analiz şarttır.

- **Organize Ağ Tespiti:** Aynı satıcının farklı ürünlerine, hep aynı 5 kişilik grubun koordineli şekilde (birbiri ardına) 5 yıldız atması.
- **Topoloji:** `(Kullanıcı)-[:YORUM_YAPTI]->(Ürün)<-[:AİTTİR]-(Satıcı)` graph kurgusu üzerinden, şüpheli IP veya kullanıcıların merkezileştiği düğümlerin kümeleme (Clustering) algoritmalarıyla (örneğin Louvain, PageRank varyasyonları) tespit edilmesi.
