from pydantic import BaseModel, HttpUrl
from typing import Optional, List, Dict, Any

class ScanRequest(BaseModel):
    """Flutter mobil uygulama veya web extension'dan gelen tarama isteği şeması."""
    url: HttpUrl
    platform: Optional[str] = None          # Örn: 'trendyol', 'hepsiburada'
    # Flutter WebView kazıyıcısının gönderdiği alanlar:
    html_content: Optional[str] = None      # Sayfa DOM içeriği (fallback scraper için)
    text_content: Optional[str] = None      # Sayfa düz metin içeriği (fallback için)
    extracted_data: Optional[Dict[str, Any]] = None  # JS kazıyıcı tarafından çıkarılan yapılandırılmış veri

class ScanResponse(BaseModel):
    """Tarama başlatıldığında API'nin döndüğü anında yanıt şeması."""
    task_id: str
    message: str
    status: str = "PENDING"

class ScanStatusResponse(BaseModel):
    """Frontend'in belirli periyotlarla (polling) arka plandaki görevi sorduğu zaman dönen şema."""
    task_id: str
    status: str                     # "PENDING", "PROCESSING", "COMPLETED", "FAILED"
    progress_percentage: int        # 0 - 100
    current_step: str               # "Yorumlar kazınıyor...", "NLP Analizi yapılıyor..." vb.
    
    # İşlem bittiyse (COMPLETED) doldurulacak nihai rapor
    result: Optional[Dict[str, Any]] = None 
    error_message: Optional[str] = None
