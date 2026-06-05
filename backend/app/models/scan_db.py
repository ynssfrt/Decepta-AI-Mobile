from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
import uuid
from app.database import Base

class Scan(Base):
    __tablename__ = "scans"

    id = Column(String, primary_key=True, index=True, default=lambda: str(uuid.uuid4()))
    url = Column(String)
    platform_score = Column(Float)
    true_trust_score = Column(Float)
    bot_percentage = Column(Integer)
    total_ratings = Column(Integer)
    total_reviews = Column(Integer)
    photo_reviews_count = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    suspicious_reviews = relationship("SuspiciousReview", back_populates="scan")

class SuspiciousReview(Base):
    __tablename__ = "suspicious_reviews"

    id = Column(Integer, primary_key=True, index=True)
    scan_id = Column(String, ForeignKey("scans.id"))
    text = Column(String)
    reason = Column(String)
    
    scan = relationship("Scan", back_populates="suspicious_reviews")
