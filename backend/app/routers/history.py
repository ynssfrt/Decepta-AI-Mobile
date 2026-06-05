from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from app.database import get_db
from app.models import scan_db
from pydantic import BaseModel
from datetime import datetime

router = APIRouter()

class SuspiciousReviewOut(BaseModel):
    text: str
    reason: str

class ScanHistoryOut(BaseModel):
    id: str
    url: str
    platform_score: float
    true_trust_score: float
    bot_percentage: int
    total_ratings: int
    total_reviews: int
    photo_reviews_count: int
    created_at: datetime
    suspicious_reviews: List[SuspiciousReviewOut]

    class Config:
        from_attributes = True

@router.get("/", response_model=List[ScanHistoryOut])
def get_all_history(db: Session = Depends(get_db)):
    """Tüm geçmiş taramaları (mobil uygulama için) listeler."""
    scans = db.query(scan_db.Scan).order_by(scan_db.Scan.created_at.desc()).all()
    return scans

@router.get("/{scan_id}", response_model=ScanHistoryOut)
def get_scan_detail(scan_id: str, db: Session = Depends(get_db)):
    """Belirli bir taramanın tüm detaylarını getirir."""
    scan = db.query(scan_db.Scan).filter(scan_db.Scan.id == scan_id).first()
    if not scan:
        raise HTTPException(status_code=404, detail="Analiz kaydı bulunamadı.")
    return scan
