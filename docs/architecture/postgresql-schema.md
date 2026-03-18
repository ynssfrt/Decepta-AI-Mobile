# PostgreSQL Veritabanı Şeması

Decepta AI uygulamasının ana veri omurgası (SOT - Source of Truth) PostgreSQL'dir. Kullanıcılar, ürünler ve NLP tarafında duygu analizi tamamlanan yorumların kayıtları burada tutulur.

## Varlık İlişki Diyagramı (ERD)

Aşağıdaki şema, sistemde tuttuğumuz ana tabloları ve birbirleriyle olan PK/FK (Primary Key / Foreign Key) bağlarını göstermektedir.

```mermaid
erDiagram
    USERS {
        uuid id PK
        string email
        string password_hash
        string role "Admin, Analyst, User"
        timestamp created_at
    }

    PLATFORMS {
        int id PK
        string name "Örn; Trendyol, Amazon"
        string domain
    }

    PRODUCTS {
        uuid id PK
        int platform_id FK
        string external_id "Platformun kendi ürün ID'si"
        string title
        string url
        int total_reviews "Çekilen toplam yorum adeti"
        timestamp created_at
    }

    REVIEWS {
        uuid id PK
        uuid product_id FK
        string external_author_id "Yorumu yapanın platformdaki no'su"
        string author_name "Yorumcu adı"
        text content "Yorum metni"
        int rating "1-5 arası yıldız"
        timestamp date "Yorumun atıldığı tarih"
        float sentiment_score "-1.0 ile 1.0 arası"
        boolean is_flagged "AI tarafından şüpheli bulundu mu?"
    }

    ANALYSIS_REPORTS {
        uuid id PK
        uuid product_id FK
        float true_trust_score "1-5 arası gerçek skor"
        float bot_percentage "Örn; %65"
        jsonb report_data "Detaylı grafik ve kelime ağacı verisi"
        timestamp calculated_at
    }

    PLATFORMS ||--o{ PRODUCTS : "has"
    PRODUCTS ||--o{ REVIEWS : "includes"
    PRODUCTS ||--|| ANALYSIS_REPORTS : "generates"
    USERS ||--o{ ANALYSIS_REPORTS : "views"
```

## Tablo Detayları

1. **`USERS`:** B2B web panelini kullanan analistlerin ve B2C mobil uygulamayı kullanan tüketicilerin giriş bilgilerini tutar.
2. **`PLATFORMS`:** Desteklenen e-ticaret siteleri. İleride yeni bir site (Örneğin: Hepsiburada) eklendiğinde buraya dahil edilecektir.
3. **`PRODUCTS`:** Analiz için sisteme linki girilen ürünlerin üst verisi (meta-data). Ayn ürün tekrar sorgulanırsa veritabanından getirilir.
4. **`REVIEWS`:** NLP (Doğal Dil İşleme) motorumuzun sonuçlarını (`sentiment_score`, `is_flagged`) sakladığımız asıl kritik tablo.
5. **`ANALYSIS_REPORTS`:** NLP ve Graph DB'den gelen sonuçların harmanlanıp JSON formatında mobil ve web arayüzüne gönderilmek üzere "Önbelleklendiği (Cached)" tablodur.
