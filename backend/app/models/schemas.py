from pydantic import BaseModel, HttpUrl
from typing import Optional, List, Dict, Any

class ScanRequest(BaseModel):
    """Kullanıcının/Analistin taratmak için girdiği e-ticaret yorum URL'si şeması."""
    url: HttpUrl
    platform: Optional[str] = None  # Örn: 'trendyol', 'amazon' - Eğer null ise URL'den tespit edilir

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
