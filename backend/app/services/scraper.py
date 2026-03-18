import time
import random
import logging
import asyncio

logger = logging.getLogger(__name__)

class BaseScraper:
    """
    E-ticaret sitelerinden yorum çekmek için kullanılacak temel sınıf.
    Gerçek dünya uygulamasında BeautifulSoup (bs4) ve/veya Selenium_driverless ile geliştirilir.
    """
    
    def __init__(self, url: str):
        self.url = str(url)
        # Bizi bot sanmasınlar diye popüler User-Agent listesi
        self.user_agents = [
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15'
        ]

    def _get_random_headers(self) -> dict:
        return {
            'User-Agent': random.choice(self.user_agents),
            'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
            'Connection': 'keep-alive'
        }

    async def fetch_reviews(self, max_pages: int = 5) -> list:
        """
        Gidilen URL'deki yorumları sayfa sayfa kazır.
        Not: Bu metod eğitim/prototip amacıyla mock (sahte) veri döner. Canlıda bs4 ile request atılır.

        Returns:
            list: [{"author_id": "...", "text": "...", "rating": 5, "date": "2025-01-01"}, ...]
        """
        logger.info(f"Scraping başlatılıyor: {self.url}")
        reviews = []
        
        # Gerçek bir scraping simülasyonu: Her sayfa arası 2-3 saniye bekleme (Cloudflare'a yakalanmamak için)
        for page in range(1, max_pages + 1):
            logger.info(f"Sayfa {page} kazınıyor...")
            await asyncio.sleep(random.uniform(1.0, 2.5)) 
            
            # Sahte veri (Mock Data) üretimi - Prototip aşaması için
            for i in range(10):  # Sayfa başı 10 yorum
                is_bot_like = random.random() < 0.3  # %30 ihtimalle sahte/abartılı yorum üret
                
                if is_bot_like:
                    text = "Ürün mükemmel harika bayıldım kesinlikle alın aldırın sorunsuz!!"
                    rating = 5
                    author_id = f"bot_candidate_{random.randint(100, 999)}"
                else:
                    text = "Ürün elime 2 günde ulaştı, kutulama fena değildi. Şimdilik memnunum."
                    rating = random.choice([3, 4, 5])
                    author_id = f"real_user_{random.randint(1000, 9999)}"
                
                reviews.append({
                    "author_id": author_id,
                    "text": text,
                    "rating": rating,
                    "date": "2025-03-15"
                })

        logger.info(f"Toplam {len(reviews)} yorum başarıyla çekildi.")
        return reviews
