import asyncio
import uuid
import logging
import random
from typing import Dict
from fastapi import APIRouter, BackgroundTasks, HTTPException, Request

from app.models.schemas import ScanRequest, ScanResponse, ScanStatusResponse
from app.services.scraper import PlaywrightScraper
from app.services.image_analyzer import ImageAnalyzer
from app.database import SessionLocal
from app.models import scan_db

logger = logging.getLogger(__name__)

router = APIRouter()
TASKS_DB: Dict[str, dict] = {}

async def _run_analysis_pipeline(task_id: str, url: str, sentiment_analyzer, html_content: str = None, text_content: str = None, extracted_data: dict = None):
    try:
        TASKS_DB[task_id]["status"] = "PROCESSING"
        TASKS_DB[task_id]["current_step"] = "1/3: Başlatılıyor..."
        TASKS_DB[task_id]["progress"] = 15

        # ---- VERİ KAYNAĞI SEÇİMİ ----
        detailed_reviews = []
        if extracted_data:
            # Extension veri gönderdi - DOĞRUDAN kullan, scraper'a DÜŞME
            actual_platform_score = float(extracted_data.get("score", 0)) or 4.5
            total_ratings = int(extracted_data.get("total_ratings", 0))
            total_reviews = int(extracted_data.get("total_reviews", 0))
            real_comments = extracted_data.get("comments", [])
            detailed_reviews = extracted_data.get("detailed_reviews", [])
                
            logger.info(f"[EXT] Score={actual_platform_score}, Ratings={total_ratings}, Reviews={total_reviews}, Comments={len(real_comments)}")
            TASKS_DB[task_id]["current_step"] = "1/3: Extension verileri alındı..."
        else:
            # Extension veri çıkaramadı veya extension kullanılmadı - scraper ile dene
            logger.info(f"[SCRAPER] Extension verisi yok/boş, Playwright scraper devreye giriyor...")
            scraper = PlaywrightScraper(url)
            
            if html_content and text_content:
                from bs4 import BeautifulSoup
                scraper.html_content = html_content
                scraper.text_content = text_content
                scraper.soup = BeautifulSoup(html_content, "html.parser")
                scraper.is_waf_blocked = False
                TASKS_DB[task_id]["current_step"] = "1/3: Extension raw DOM işleniyor..."
            else:
                TASKS_DB[task_id]["current_step"] = "1/3: Headless tarayıcı ile kazınıyor..."
                await scraper.fetch_page()
            
            actual_platform_score = scraper.extract_score()
            total_ratings, total_reviews = scraper.extract_metrics()
            real_comments = scraper.extract_real_comments()
            
            logger.info(f"[SCRAPER] Score={actual_platform_score}, Ratings={total_ratings}, Yorumlar={len(real_comments)}")

        TASKS_DB[task_id]["current_step"] = "1/3: Dinamik DOM Verileri İşleniyor..."
        TASKS_DB[task_id]["progress"] = 35
        
        true_review_count = total_reviews if total_reviews > 0 else len(real_comments)
        
        # Yorumları ReviewDetector formatına dönüştür ve zenginleştir
        review_dicts = []
        if detailed_reviews:
            for r in detailed_reviews:
                review_dicts.append({
                    "text": r.get("text", ""),
                    "images": r.get("images", []),
                    "rating": r.get("rating"),
                    "date": r.get("date"),
                    "author": r.get("author")
                })
        else:
            # Fallback: Eğer detailed_reviews yoksa real_comments listesinden üret
            for c in real_comments:
                review_dicts.append({
                    "text": c,
                    "images": [],
                    "rating": None,
                    "date": None,
                    "author": None
                })
        
        suspicious_list = []
        
        # Resim Analizi Modülü (Computer Vision)
        TASKS_DB[task_id]["current_step"] = "2/3: Görüntü Analizi Yapılıyor..."
        TASKS_DB[task_id]["progress"] = 50
        
        photo_reviews_count = 0
        # Öncelik: Extension'dan doğrudan gelen photo_reviews_count
        if extracted_data and extracted_data.get("photo_reviews_count"):
            photo_reviews_count = int(extracted_data.get("photo_reviews_count", 0))
        # Fallback: detailed_reviews içinden say
        elif detailed_reviews:
            photo_reviews_count = sum(1 for r in detailed_reviews if r.get("images"))
        
        if detailed_reviews:
            try:
                image_analyzer = ImageAnalyzer()
                img_suspicious = image_analyzer.analyze_images(detailed_reviews)
                suspicious_list.extend(img_suspicious)
            except Exception as img_err:
                logger.warning(f"Görüntü analizi başarısız (devam ediliyor): {img_err}")
            
        TASKS_DB[task_id]["current_step"] = f"2/3: NLP ve Gelişmiş Ağ Analizi Yapılıyor ({len(review_dicts)} organik değerlendirme)..."
        TASKS_DB[task_id]["progress"] = 65
        
        if len(review_dicts) <= 2:
            bot_percentage = 0
            true_trust_score = actual_platform_score
        else:
            from ai.src.detection.detector import ReviewDetector
            detector = ReviewDetector()
            
            # Gelişmiş Tespit Algoritmalarını Çalıştır
            detection_result = detector.detect(review_dicts, sentiment_analyzer, actual_platform_score)
            
            # Detektörden gelen şüphelileri ekle
            suspicious_list.extend(detection_result["suspicious_reviews"])
            
            # Resim ve NLP analizinden gelen şüpheleri birleştir (metin bazlı tekilleştir)
            merged_suspicious = {}
            for s in suspicious_list:
                text = s.get("text", "").strip()
                reason = s.get("reason", "").strip()
                if not text:
                    continue
                if text in merged_suspicious:
                    existing_reasons = [r.strip() for r in merged_suspicious[text]["reason"].split("ve")]
                    if reason not in existing_reasons:
                        merged_suspicious[text]["reason"] += " ve " + reason
                else:
                    merged_suspicious[text] = {"text": text, "reason": reason}
                    
            suspicious_list = list(merged_suspicious.values())
            
            # bot_percentage'ı birleştirme sonrası GERÇEK şüpheli sayısından hesapla
            # (Detektörün orijinal değeri sadece NLP sonuçlarını kapsar;
            #  ImageAnalyzer'dan gelen ekstra bulgular dahil değildir)
            bot_percentage = int((len(suspicious_list) / max(1, true_review_count)) * 100) if true_review_count > 0 else detection_result["bot_percentage"]
            true_trust_score = detection_result["calculated_trust_score"]

        TASKS_DB[task_id]["current_step"] = "3/3: Ağ Analizi Tamamlanıyor..."
        TASKS_DB[task_id]["progress"] = 85
        await asyncio.sleep(1.0)

        TASKS_DB[task_id]["status"] = "COMPLETED"
        TASKS_DB[task_id]["progress"] = 100
        TASKS_DB[task_id]["current_step"] = "Analiz Tamamlandı!"
        TASKS_DB[task_id]["result"] = {
            "platform_score": actual_platform_score, 
            "true_trust_score": true_trust_score,
            "bot_percentage": bot_percentage,
            "total_ratings": total_ratings,
            "total_reviews": true_review_count,
            "photo_reviews_count": photo_reviews_count,
            "suspicious_reviews": suspicious_list
        }

        # ---- VERİTABANINA KAYDET (Mobil Senkronizasyon İçin) ----
        try:
            db = SessionLocal()
            new_scan = scan_db.Scan(
                id=task_id,
                url=url,
                platform_score=actual_platform_score,
                true_trust_score=true_trust_score,
                bot_percentage=bot_percentage,
                total_ratings=total_ratings,
                total_reviews=true_review_count,
                photo_reviews_count=photo_reviews_count
            )
            db.add(new_scan)
            
            for sus in suspicious_list:
                db.add(scan_db.SuspiciousReview(
                    scan_id=task_id,
                    text=sus.get("text", ""),
                    reason=sus.get("reason", "")
                ))
            
            db.commit()
            db.close()
            logger.info(f"Veritabanına başarıyla kaydedildi: {task_id}")
        except Exception as db_err:
            logger.error(f"Veritabanı kayıt hatası: {db_err}")

        
    except Exception as e:
        logger.error(f"Pipeline Hatası: {str(e)}", exc_info=True)
        TASKS_DB[task_id]["status"] = "FAILED"
        TASKS_DB[task_id]["error_message"] = str(e)

# ---- DEBUG ENDPOINT: Extension'ın ne gönderdiğini görmek için ----
@router.post("/debug")
async def debug_scan(request_data: ScanRequest):
    """Extension'dan gelen ham veriyi debug etmek için kullanılır."""
    return {
        "url": str(request_data.url),
        "has_html": bool(request_data.html_content),
        "html_length": len(request_data.html_content) if request_data.html_content else 0,
        "has_extracted_data": bool(request_data.extracted_data),
        "extracted_data": request_data.extracted_data
    }

@router.post("/", response_model=ScanResponse)
async def start_scan(request_data: ScanRequest, background_tasks: BackgroundTasks, request: Request):
    sentiment_analyzer = request.app.state.sentiment_analyzer
    task_id = str(uuid.uuid4())
    TASKS_DB[task_id] = {
        "status": "QUEUED",
        "progress": 0,
        "current_step": "Sıraya Alındı",
        "result": None,
        "error_message": None
    }
    background_tasks.add_task(
        _run_analysis_pipeline, 
        task_id, 
        str(request_data.url), 
        sentiment_analyzer,
        request_data.html_content,
        request_data.text_content,
        request_data.extracted_data
    )
    return ScanResponse(task_id=task_id, message="Sıraya alındı.")

@router.get("/{task_id}", response_model=ScanStatusResponse)
async def check_scan_status(task_id: str):
    task = TASKS_DB.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Bulunamadı")
    return ScanStatusResponse(
        task_id=task_id, status=task["status"], progress_percentage=task["progress"],
        current_step=task["current_step"], result=task["result"], error_message=task["error_message"]
    )
