import asyncio
import logging
import re
import requests
from bs4 import BeautifulSoup
import string

logger = logging.getLogger(__name__)

class BaseScraper:
    def __init__(self, url: str):
        self.url = str(url)
        self.user_agents = [
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15'
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
                
                # SCRIPT ve STYLE etiketlerini çöpe at (Arayüz kodlarını okumasın)
                for script in self.soup(["script", "style", "noscript", "meta"]):
                    script.extract()
            else:
                logger.warning(f"Bağlantı blokesi (Status: {response.status_code}).")
        except Exception as e:
            logger.error(f"Scraping Hatası: {str(e)}")

    def extract_score(self) -> float:
        if not self.html_content:
            return 4.5
        match = re.search(r'(?<![0-9])([1-4][.,][0-9]|5[.,]0)(?![0-9])', self.html_content)
        if match:
            extracted = float(match.group(1).replace(',', '.'))
            if 1.0 <= extracted <= 5.0:
                return extracted
        return 4.5

    def extract_reviews_from_html(self) -> list:
        if not self.soup:
            return []
            
        reviews = []
        # Sayfadaki tüm görünür metinleri al (Soup get_text() scriptleri sildikten sonra temizdir)
        text_nodes = self.soup.stripped_strings
        
        for text in text_nodes:
            # Sadece makul uzunluktaki ve kelimeler barındıran cümleleri al
            if 30 <= len(text) <= 500 and text.count(' ') > 3:
                # Kod kalıntılarını veya UI linklerini filtrele
                text_lower = text.lower()
                bad_words = ["ücretsiz kargo", "sepete ekle", "taksit seçenekleri", "giriş yap", "{", "}", "function", "var ", "let "]
                if not any(bw in text_lower for bw in bad_words):
                    reviews.append(text)
                    
        return list(set(reviews))
    
    def extract_ngrams(self, text_list, n=2, top_k=3):
        if not text_list:
            return []
            
        words = []
        for text in text_list:
            # Harf ve rakam dışındakileri temizle
            clean_text = re.sub(r'[^\w\s]', '', text).lower()
            words.extend(clean_text.split())
            
        ngrams = []
        if len(words) >= n:
            for i in range(len(words) - n + 1):
                ngram = " ".join(words[i:i+n])
                # Çok kısa kelimelerden oluşan n-gramları alma (örneğin "ve bu")
                if len(ngram) > 8:
                    ngrams.append(ngram)
        
        import collections
        counter = collections.Counter(ngrams)
        most_common = [item[0] for item in counter.most_common(top_k)]
        return most_common or []
