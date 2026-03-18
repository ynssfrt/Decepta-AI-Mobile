# Neo4j Graph Veritabanı Şeması

Neo4j, Decepta AI sisteminin **siber istihbarat** modülüdür. Yorum yapan profiller arasındaki bağlantıları, suç kümelerini (kümeleme) ve koordine eylemleri (organize bot ağları) tespit etmek için kullanılır.

Relational (PostgreSQL) yapılardaki tablolar arası JOIN yükünden kurtulup "Şu hesaba en çok benzeyen hesaplar hangisi?" sorusuna anında yanıt verebilir.

## Graph Diyagramı (Düğüm ve İlişkiler)

Aşağıdaki diyagram sistemin düğüm (Node) ve kenarlarını (Edge/Relationship) göstermektedir.

```mermaid
graph TD
    classDef userNode fill:#f9d0c4,stroke:#333,stroke-width:2px;
    classDef reviewNode fill:#d4e6f1,stroke:#333,stroke-width:2px;
    classDef productNode fill:#d5f5e3,stroke:#333,stroke-width:2px;
    classDef ipNode fill:#fcf3cf,stroke:#333,stroke-width:2px;

    U1((User Profile)):::userNode
    U2((User Profile)):::userNode
    R1[Review]:::reviewNode
    R2[Review]:::reviewNode
    P1{Product}:::productNode
    IP((IP or Subnet)):::ipNode

    U1 -- WROTE {date: 2025-01-01} --> R1
    U2 -- WROTE {date: 2025-01-01} --> R2
    
    R1 -- BELONGS_TO --> P1
    R2 -- BELONGS_TO --> P1
    
    U1 -- HAS_IP --> IP
    U2 -- HAS_IP --> IP

    U1 -. SAME_NETWORK_AS {similarity: 0.95} .- U2

    %% Styling and layout hints
    style U1 stroke:#e74c3c
    style U2 stroke:#e74c3c
```

## Düğümler (Nodes)

- **`User` (Kullanıcı Profili):** E-ticaret platformundaki profil numarasıdır. Uygulamamıza kayıtlı kişi değil, "Trendyol kullanıcısı Ahmet123" gibi bir Dış Profil'dir. 
  - *Özellikler:* `platform_user_id`, `name`, `join_date`
- **`Review` (Yorum):** Yorum olayıdır. 
  - *Özellikler:* `review_id`, `rating`, `sentiment_score` 
- **`Product` (Ürün):** E-ticaret sitesindeki üründür.
  - *Özellikler:* `external_id`, `category`
- **`IP_Subnet` (Sanal Ağ):** Eğer web scraping aşamasında kullanıcıların coğrafi verisi/zaman dilimi çıkarılabilirse kümeleme yapmak için kullanılır.

## Kritik İlişkiler (Edges) ve Senaryolar

1. **Toplu Tetiklenme (Swarm Attack):**
   100 farklı `User`'ın aynı gün ( `WROTE.date` özellikleri aynı ) aynı `Product`'a 5 yıldız vermesi durumu, Graph PageRank algoritması ile merkezcil bir anomali doğurur ve kümeyi komple `is_flagged = True` moduna sokar.
2. **Kopya Karakter (Similarity):**
   İki `User`, sürekli aynı ürünlere ("A markasının" kulaklığı, faresi, kamerası) tam puan veriyorsa, arka planda algoritma bu iki User arasında `[:SAME_NETWORK_AS]` ilişkisi yaratır. Bu ilişki zinciri uzadığında devasa bir bot ağı görseli ortaya çıkar.
