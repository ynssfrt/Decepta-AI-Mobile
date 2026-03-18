import asyncio
import logging
import re
import json
from playwright.async_api import async_playwright
from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)

class PlaywrightScraper:
    def __init__(self, url: str):
        self.url = str(url)
        self.html_content = ""
        self.text_content = ""
        self.soup = None

    async def fetch_page(self):
        try:
            logger.info(f"Playwright başlatılıyor: {self.url}")
            async with async_playwright() as p:
                browser = await p.chromium.launch(headless=True)
                page = await browser.new_page(
                    user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                )
                
                await page.goto(self.url, wait_until="domcontentloaded", timeout=45000)
                
                # Yavaş kaydırma (Lazy Load yorumları tetiklemek için)
                for i in range(1, 6):
                    await page.evaluate(f"window.scrollTo(0, document.body.scrollHeight * {i/5})")
                    await page.wait_for_timeout(800)
                
                # Biraz daha bekle tam yüklensin
                await page.wait_for_timeout(2000)

                self.html_content = await page.content()
                self.text_content = await page.evaluate("document.body.innerText")
                self.soup = BeautifulSoup(self.html_content, "html.parser")
                
                await browser.close()
        except Exception as e:
            logger.error(f"Playwright Hatası: {str(e)}")

    def _extract_from_jsonld(self):
        """Standardize e-ticaret sitelerinin arka planda sakladığı tam kesin veri tabanını (JSON-LD) okur."""
        if not self.soup: return None, None, None
        
        for script in self.soup.find_all("script", type="application/ld+json"):
            try:
                data = json.loads(script.string)
                # JSON-LD içeriği bazen liste, bazen dikte olabilir
                if isinstance(data, list):
                    for item in data:
                        if "aggregateRating" in item:
                            agg = item["aggregateRating"]
                            return float(agg.get("ratingValue", 0)), int(agg.get("reviewCount", 0)), int(agg.get("ratingCount", 0))
                elif isinstance(data, dict):
                    if "aggregateRating" in data:
                        agg = data["aggregateRating"]
                        return float(agg.get("ratingValue", 0)), int(agg.get("reviewCount", 0)), int(agg.get("ratingCount", 0))
            except:
                pass
        return None, None, None

    def extract_score(self) -> float:
        # 1. Öncelik: Kesin SEO verisi JSON-LD
        score, rev_c, rat_c = self._extract_from_jsonld()
        if score and 1.0 <= score <= 5.0:
            return round(score, 1)
            
        # 2. Öncelik: Ekrandaki spesifik e-ticaret (Örn: Trendyol) elementleri
        if self.soup:
            trendyol_score = self.soup.find(class_='pr-in-rnr-v')
            if trendyol_score:
                try:
                    return float(trendyol_score.text.strip().replace(',', '.'))
                except: pass
                
        # 3. Öncelik: Regex ile ilk mantıklı skoru bul (Değerlendirme metni yakınlarındaki)
        if self.text_content:
            # "Değerlendirme" veya "Yorum" kelimesinden önceki ilk [1-5],[0-9] arası rakamı bulmaya çalış
            match = re.search(r'([1-4][.,][0-9]|5[.,]0)[\s\S]{0,50}(?:değerlendirme|yorum|oy)', self.text_content.lower())
            if match:
                return float(match.group(1).replace(',', '.'))
                
        return 4.5 # Fallback

    def extract_metrics(self) -> tuple:
        # Toplam Değerlendirme, Toplam Yazılı Yorum
        score, rev_c, rat_c = self._extract_from_jsonld()
        
        total_ratings = rat_c if rat_c else 0
        total_reviews = rev_c if rev_c else 0
        
        # Eğer JSON-LD boşsa veya eksikse, Regex ile sayfadan (Örn: "33 Değerlendirme") tara
        if total_ratings == 0:
            if self.soup:
                tr_count = self.soup.find(class_='rvw-cnt-tx')
                if tr_count:
                    nums = re.findall(r'\d+', tr_count.text.replace('.', ''))
                    if nums: total_ratings = int(nums[0])
            
            if total_ratings == 0 and self.text_content:
                # Ekranda direkt "33 değerlendirme" arar
                match = re.search(r'([0-9.,]+)\s+(?:değerlendirme|oy|kişi)', self.text_content.lower())
                if match:
                    try:
                        total_ratings = int(match.group(1).replace('.', '').replace(',', ''))
                    except: pass
                    
        # Yorum sayısı genelde değerlendirmeden farklıdır. Yoksa aynı alırız.
        if total_reviews == 0 and self.text_content:
            match = re.search(r'([0-9.,]+)\s+(?:yorum|soru)', self.text_content.lower())
            if match:
                try:
                    total_reviews = int(match.group(1).replace('.', '').replace(',', ''))
                except: pass
                
        # Garanti olması açısından mantık kontrölü
        if total_reviews > total_ratings and total_ratings > 0:
            total_reviews = total_ratings // 3
            
        return total_ratings, total_reviews

    def extract_real_comments(self) -> list:
        if not self.soup:
            return []
            
        comments = []
        for script in self.soup(["script", "style", "noscript", "meta", "svg", "path"]):
            script.extract()
            
        for text in self.soup.stripped_strings:
            if 30 <= len(text) <= 600 and text.count(' ') > 3:
                txt_lower = text.lower()
                bad_words = ["ücretsiz", "kargo", "sepete ekle", "taksit", "giriş yap", "üye ol", "kategoriler", "hakkımızda", "yardım", "iletişim"]
                if not any(bw in txt_lower for bw in bad_words):
                    comments.append(text)
        
        return list(set(comments))
