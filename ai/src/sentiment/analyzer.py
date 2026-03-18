import logging
from transformers import pipeline

logger = logging.getLogger(__name__)

class SentimentAnalyzer:
    """
    HuggingFace modellerini kullanarak e-ticaret yorumlarının duygu analizini (Sentiment) hesaplar.
    Varsayılan model: dbmdz/bert-base-turkish-cased (Türkçe metinler için eğitilmiş)
    """

    def __init__(self, model_name: str = "savasy/bert-base-turkish-sentiment-cased"):
        """
        Modeli hafızaya yükler.
        Ağır bir işlem olduğu için uygulama ayağa kalkarken (Singleton) 1 kere çalıştırılmalıdır.
        """
        self.model_name = model_name
        self.analyzer = None
        
        try:
            logger.info(f"Model yükleniyor: {self.model_name}")
            # HuggingFace pipeline otomatik olarak modeli indirip yükler
            self.analyzer = pipeline("sentiment-analysis", model=self.model_name)
            logger.info("Model başarıyla yüklendi.")
        except Exception as e:
            logger.error(f"HuggingFace model yüklenirken hata oluştu: {str(e)}")
            # Fallback (Dummy) mekanizması
            self.analyzer = None

    def analyze(self, text: str) -> dict:
        """
        Verilen metnin duygu analizini yapar.
        
        Returns:
            dict: {
                "label": "POSITIVE" | "NEGATIVE",
                "score": 0.0 - 1.0 (Güven skoru)
            }
        """
        if not text or not text.strip():
            return {"label": "NEUTRAL", "score": 0.0}

        if self.analyzer is None:
             # Eğer pipeline yüklenemediyse dummy bir yanıt dön (Geliştirme/test ortamı için)
             return {"label": "UNKNOWN", "score": 0.5}

        try:
            # Model max_length kısıtı olabilir (genelde 512 token)
            # Eğer yorum çok uzunsa keski işlemi (truncation) pipeline tarafından yapılır.
            result = self.analyzer(text)[0]
            
            # Model çıktılarını standartlaştırma
            # Bazı modeller LABEL_1, LABEL_0 dönebilir. (savasy modeli pozitif/negatif döner)
            label = result.get('label', '').upper()
            score = float(result.get('score', 0.5))
            
            # Etiket düzeltmesi (savasy modelinde genellike positive/negative dir)
            if "LABEL_1" in label or "POS" in label:
                normalized_label = "POSITIVE"
            elif "LABEL_0" in label or "NEG" in label:
                normalized_label = "NEGATIVE"
            else:
                normalized_label = label
                
            return {
                "label": normalized_label,
                "score": score
            }
        except Exception as e:
            logger.error(f"Duygu analizi sırasında hata: {str(e)}")
            return {"label": "ERROR", "score": 0.0}
