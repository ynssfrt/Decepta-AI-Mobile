import sys
import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import logging

# ai/ paketini sys.path'e ekle (detector, sentiment, preprocessing modüllerine erişim için)
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))

from app.routers import scanner, history
from app.database import engine
from app.models import scan_db

# Veritabanı tablolarını oluştur (scans, suspicious_reviews)
scan_db.Base.metadata.create_all(bind=engine)

logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Uygulama başlarken NLP modelini yükle (warm-up)
    logger.info("Yapay zeka modeli yükleniyor...")
    from ai.src.sentiment.analyzer import SentimentAnalyzer
    app.state.sentiment_analyzer = SentimentAnalyzer()
    logger.info("Model hazır.")
    yield
    logger.info("Uygulama kapanıyor...")

app = FastAPI(
    title="Decepta AI - Backend API",
    description="E-Ticaret Sahte Yorum ve Bot Ağı Tespit Platformu Merkezi API'si",
    version="1.0.0",
    lifespan=lifespan
)

# CORS Ayarları: Mobil uygulama (Android emülatör: 10.0.2.2) ve Web Dashboard erişimi için
origins = [
    "http://localhost:3000",
    "http://localhost:5173",
    "http://localhost:8080",
    "*"  # Geliştirme aşamasında açık; canlıda kısıtlanmalı
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Router'lar
app.include_router(scanner.router, prefix="/api/v1/scan", tags=["Scanner"])
app.include_router(history.router, prefix="/api/v1/history", tags=["History"])

@app.get("/")
async def root():
    return {
        "status": "online",
        "message": "Decepta AI Backend Servisi Çalışıyor.",
        "docs": "/docs"
    }

