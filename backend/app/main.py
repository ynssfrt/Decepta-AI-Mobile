from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import scanner

app = FastAPI(
    title="Decepta AI - Backend API",
    description="E-Ticaret Sahte Yorum ve Bot Ağı Tespit Platformu Merkezi API'si",
    version="1.0.0"
)

# CORS Ayarları: Web Dashboard ve Mobile App'in lokalde/sunucuda API'ye erişebilmesi için
origins = [
    "http://localhost:3000",      # React / Next.js Web Dashboard
    "http://localhost:8080",
    "*"                           # Geliştirme aşamasında her şeye açık, canlıda kısıtlanmalı
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Router'ları (Endpoint Kontrolcüleri) ana uygulamaya bağlıyoruz
app.include_router(scanner.router, prefix="/api/v1/scan", tags=["Scanner"])

@app.get("/")
async def root():
    return {
        "status": "online",
        "message": "Decepta AI Backend Servisi Çalışıyor.",
        "docs": "/docs"
    }
