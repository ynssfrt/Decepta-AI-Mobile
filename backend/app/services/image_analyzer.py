import logging
import urllib.request
import hashlib

logger = logging.getLogger(__name__)

class ImageAnalyzer:
    """
    Yorumlardaki fotoğrafların hash değerlerini çıkarıp, 
    kopya görsel (farklı hesaplardan yüklenen aynı görsel) tespitini yapar.
    (Not: Ağ sorunları nedeniyle ImageHash yerine MD5 ile birebir kopya tespiti yapıyoruz)
    """
    def __init__(self):
        self.hashes = {} # {hash_string: [image_url1, image_url2]}
        
    def download_image_bytes(self, url: str) -> bytes:
        try:
            req = urllib.request.Request(
                url, 
                headers={'User-Agent': 'Mozilla/5.0'}
            )
            with urllib.request.urlopen(req, timeout=5) as response:
                return response.read()
        except Exception as e:
            logger.warning(f"Resim indirilemedi ({url}): {e}")
            return None

    def analyze_images(self, reviews_with_images: list) -> list:
        suspicious_list = []
        self.hashes = {}
        
        for review in reviews_with_images:
            images = review.get('images', [])
            if not images:
                continue
                
            is_duplicate_found = False
            
            for img_url in images:
                img_data = self.download_image_bytes(img_url)
                if not img_data:
                    continue
                
                try:
                    h = hashlib.md5(img_data).hexdigest()
                except Exception as e:
                    logger.error(f"Hash çıkarma hatası: {e}")
                    continue
                
                matched = False
                if h in self.hashes:
                    self.hashes[h].append(img_url)
                    matched = True
                    is_duplicate_found = True
                        
                if not matched:
                    self.hashes[h] = [img_url]
                    
            # Ek Mantık: Resim var ama yorum metni çok kısa veya boş
            text = review.get('text', '').strip()
            is_empty_text = len(text) < 3
            
            if is_duplicate_found:
                suspicious_list.append({
                    "text": text or "[Sadece Görsel]",
                    "reason": "Organize Bot Ağı Tespiti: Birebir kopya görsel kullanımı."
                })
            elif is_empty_text and images:
                suspicious_list.append({
                    "text": text or "[Sadece Görsel]",
                    "reason": "Düşük Güvenlikli Değerlendirme: Betimleyici metin içermeyen şüpheli görsel paylaşımı."
                })
                
        return suspicious_list
