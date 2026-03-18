import asyncio
import uuid
import logging
from typing import Dict
from fastapi import APIRouter, BackgroundTasks, HTTPException

from app.models.schemas import ScanRequest, ScanResponse, ScanStatusResponse
from app.services.scraper import BaseScraper

logger = logging.getLogger(__name__)

router = APIRouter()

# Geçici in-memory veritabanı (Görev durumlarını tutmak için)
# Gerçek uygulamada bu Redis veya PostgreSQL'de tutulur.
TASKS_DB: Dict[str, dict] = {}

async def _run_analysis_pipeline(task_id: str, url: str):
    """
    Arka planda (Background Task) çalışan asıl ağır işlem:
    1. Yorumları Kazı (Scraping)
    2. Metin Ön İşleme & NLP (Duygu Analizi)
    3. Graph DB (Ağ Analizi: Bot Tespiti)
    """
    try:
        # AŞAMA 1: Scraping (Kazıma) Başlat
        TASKS_DB[task_id]["status"] = "PROCESSING"
        TASKS_DB[task_id]["current_step"] = "1/3: Yorumlar Kazınıyor..."
        TASKS_DB[task_id]["progress"] = 10
        
        scraper = BaseScraper(url)
        # 3 sayfa yorum çekmeyi simüle et
        reviews = await scraper.fetch_reviews(max_pages=3) 
        
        # AŞAMA 2: NLP ve Model Analizi
        TASKS_DB[task_id]["current_step"] = f"2/3: NLP Analizi Yapılıyor ({len(reviews)} yorum)..."
        TASKS_DB[task_id]["progress"] = 50
        
        await asyncio.sleep(2.0)  # HuggingFace model yükünü simüle et
        
        # AŞAMA 3: Graph DB (Neo4j) ve Bot Ağ Tespiti
        TASKS_DB[task_id]["current_step"] = "3/3: Neo4j Bot Ağı Tespiti..."
        TASKS_DB[task_id]["progress"] = 80
        
        await asyncio.sleep(1.5)  # Cypher query simülasyonu
        
        # Final Sonuçlarını Derleme
        TASKS_DB[task_id]["status"] = "COMPLETED"
        TASKS_DB[task_id]["progress"] = 100
        TASKS_DB[task_id]["current_step"] = "Analiz Tamamlandı!"
        TASKS_DB[task_id]["result"] = {
            "platform_score": 4.8, 
            "true_trust_score": 2.3,
            "bot_percentage": 65,
            "analyzed_reviews": len(reviews),
            "suspicious_patterns": ["Harika ürün kesin alın", "mükkemmel sorunsuz"]
        }
        logger.info(f"Task {task_id} başarıyla tamamlandı.")
        
    except Exception as e:
        logger.error(f"Task {task_id} sırasında hata: {str(e)}")
        TASKS_DB[task_id]["status"] = "FAILED"
        TASKS_DB[task_id]["error_message"] = str(e)


@router.post("/", response_model=ScanResponse)
async def start_scan(request: ScanRequest, background_tasks: BackgroundTasks):
    """
    E-Ticaret linkini alır ve tarama işlemini arka planda başlatır.
    İşlem uzayacağı için (Scraping) kullanıcıya anında (200 OK) bir `task_id` döner.
    """
    task_id = str(uuid.uuid4())
    
    # Yeni görevi DB'ye kaydet
    TASKS_DB[task_id] = {
        "status": "QUEUED",
        "progress": 0,
        "current_step": "Sıraya Alındı",
        "result": None,
        "error_message": None
    }
    
    # Zorlu işlemi arka plana gönder (Uygulama kilitlenmez)
    background_tasks.add_task(_run_analysis_pipeline, task_id, str(request.url))
    
    return ScanResponse(
        task_id=task_id, 
        message="Analiz sıraya alındı. Durumu kontrol etmek için task_id kullanın."
    )

@router.get("/{task_id}", response_model=ScanStatusResponse)
async def check_scan_status(task_id: str):
    """
    Frontend (React / Flutter) bu uç noktayı her 2-3 saniyede bir çağırarak (Polling)
    veya Socket üzerinden süreç barını (Progress bar) günceller.
    """
    task = TASKS_DB.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Görev bulunamadı.")
        
    return ScanStatusResponse(
        task_id=task_id,
        status=task["status"],
        progress_percentage=task["progress"],
        current_step=task["current_step"],
        result=task["result"],
        error_message=task["error_message"]
    )
