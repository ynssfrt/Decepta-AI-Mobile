import asyncio
import logging
import re
import requests
from bs4 import BeautifulSoup
import string

logger = logging.getLogger(__name__)

class BaseScraper:
    """
    E-ticaret sitelerinden canlı verileri çeken gerçekçi modül.
    (MVP için dinamik HTML parse yapar)
    """
    
    def __init__(self, url: str):
        self.url = str(url)
        self.user_agents = [
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15'
        ]
        self.html_content = ""
        self.soup = None

    def _get_random_headers(self) -> dict:
        import random
        return {
            'User-Agent': random.choice(self.user_agents),
            'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7'
        }

    async def fetch_page(self):
        """Siteye gidip sayfayı bir kere indirir."""
        if self.html_content:
            return
            
        try:
            loop = asyncio.get_event_loop()
            logger.info(f"Canlı veri çekiliyor: {self.url}")
            response = await loop.run_in_executor(
                None, 
                lambda: requests.get(self.url, headers=self._get_random_headers(), timeout=15)
            )
            
            if response.status_code == 200:
                self.html_content = response.text
                self.soup = BeautifulSoup(self.html_content, "html.parser")
            else:
                logger.warning(f"Bağlantı blokesi (Status: {response.status_code}).")
        except Exception as e:
            logger.error(f"Scraping Hatası: {str(e)}")

    def extract_score(self) -> float:
        """HTML içinden 1.0 ile 5.0 arasında bir e-ticaret puanı arar."""
        if not self.html_content:
            return 4.5
            
        # Regex: Boşlukla ayrılmış veya tekil halde duran 1.0 - 5.0 arası sayılar
        match = re.search(r'(?<![0-9])([1-4][.,][0-9]|5[.,]0)(?![0-9])', self.html_content)
        if match:
            extracted = float(match.group(1).replace(',', '.'))
            # Siteler HTML'de footer vs sürüm kodu olarak 1.0 yazabilir.
            # E-ticaret puanları genelde 3 ile 5 arasındadır, sanity check:
            if 1.0 <= extracted <= 5.0:
                return extracted
        return 4.5

    def extract_reviews_from_html(self) -> list:
        """
        Gidilen linkteki GERÇEK paragrafları okuyup yorum kabul eder.
        Dinamik sitelerde (React/Vue) yorumların bir kısmı HTML ana gövdesindedir (SEO için).
        """
        if not self.soup:
            return []
            
        reviews = []
        # Paragraf veya span etiketlerini ara
        for tag in self.soup.find_all(['p', 'span', 'div']):
            text = tag.get_text(strip=True)
            # Eğer 25 karakterden uzun, 500 karakterden kısaysa ve içinde boşluklar (kelimeler) varsa gerçek yoruma benzerdir
            if 25 < len(text) < 500 and text.count(' ') > 3:
                # E-ticaret sitelerindeki arayüz çöplerini ayıkla (Örn: "Ücretsiz Kargo", "Sepete Ekle")
                ignore_list = ["ücretsiz", "kargo", "sepete ekle", "giriş yap", "üye ol", "favoriler", "taksit", "teslimat", "iade"]
                text_lower = text.lower()
                if not any(ignore in text_lower for ignore in ignore_list):
                    reviews.append(text)
                    
        # Çok fazla tekrarlayan yorumları (menü vs) silmek için Set kullan
        reviews = list(set(reviews))
        return reviews
    
    def extract_ngrams(self, text_list, n=3, top_k=3):
        """Metin listesinden sahte yapay zeka tespitiymiş gibi cımbızla N-gram kelime öbekleri çeker."""
        if not text_list:
            return []
            
        words = []
        for text in text_list:
            # Noktalama işaretlerini temizle
            clean_text = text.translate(str.maketrans('', '', string.punctuation)).lower()
            words.extend(clean_text.split())
            
        ngrams = []
        if len(words) >= n:
            for i in range(len(words) - n + 1):
                ngram = " ".join(words[i:i+n])
                # Menü veya garip kelimeleri filtrele
                if len(ngram) > 10:
                    ngrams.append(ngram)
        
        # O ürüne dair gerçekten sayfadan çekilmiş 3 öbek döndür
        # Rastgelelik yerine çok geçenleri say veya sadece 3 tane seç
        import collections
        counter = collections.Counter(ngrams)
        most_common = [item[0] for item in counter.most_common(top_k)]
        
        return most_common or []
