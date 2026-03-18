import re
import string

def clean_text(text: str, remove_stopwords: bool = False) -> str:
    """
    E-Ticaret yorum metnini NLP işlemleri (Duygu analizi) için hazırlamak amacıyla temizler.

    Args:
        text (str): Temizlenecek ham yorum metni.
        remove_stopwords (bool): Türkçe stop-word kelimeler çıkarılsın mı? (Varsayılan: False,
            çünkü HuggingFace transformer modelleri bağlamı anlamak için stop-word'lere ihtiyaç duyabilir).

    Returns:
        str: Temizlenmiş ve küçültülmüş metin.
    """
    if not isinstance(text, str):
        return ""

    # 1. HTML etiketlerini temizle (E-ticaret scraper'larından gelebilir)
    clean_html = re.compile('<.*?>')
    text = re.sub(clean_html, '', text)

    # 2. Küçük harfe çevirme (Türkçe karaktere uygun)
    text = text.replace('I', 'ı').replace('İ', 'i').lower()

    # 3. Fazla boşlukları ve sekmeleri temizle
    text = re.sub(r'\s+', ' ', text).strip()

    # 4. Koyu link ve URL'leri temizle (Yorumun içine botlar tarafından eklenmiş spam linkler)
    text = re.sub(r'http\S+|www.\S+', '', text)

    # 5. Art arda 3'ten fazla tekrarlayan harfleri düzelt (Örn: "harikaaaaa" -> "harikaa")
    # Bu özellik e-ticaret yorumlarında çok yaygındır ve aşırı hevesli/bot davranışları belli eder
    text = re.sub(r'(.)\1{2,}', r'\1\1', text)
    
    # 6. (Opsiyonel) Noktalama işaretlerini kaldır
    # Bazı NLP modelleri emoji ve ünlem işaretini dikkate alır, bu yüzden varsayılan olarak tutuyoruz
    # Eğer klasik Machine Learning (TF-IDF vb) kullanılacaksa çıkartılmalıdır.
    
    if remove_stopwords:
        # Basit bir Türkçe stop-words listesi
        turkish_stopwords = {"ve", "ile", "veya", "ama", "fakat", "lakin", "çünkü", "eğer", "ki", "da", "de"}
        words = text.split()
        words = [w for w in words if w not in turkish_stopwords]
        text = " ".join(words)

    return text.strip()

def calculate_text_complexity(text: str) -> dict:
    """
    Metnin kelime sayısı, karakter/kelime oranı gibi özelliklerini çıkartır.
    Botların kopyala/yapıştır benzerliklerini anlamak için şablon çıkarıcı bir özelliktir.
    """
    words = text.split()
    num_words = len(words)
    num_chars = len(text.replace(" ", ""))
    
    return {
        "word_count": num_words,
        "char_count": num_chars,
        "avg_word_length": num_chars / num_words if num_words > 0 else 0
    }
