import os
import logging
from neo4j import GraphDatabase
from typing import List, Dict, Any

logger = logging.getLogger(__name__)

class BotNetworkGraph:
    """
    Neo4j veritabanı bağlantısı kurarak organize bot ağı sorgulamaları (Cypher) yapan köprü sınıftır.
    """

    def __init__(self, uri: str = None, user: str = None, password: str = None):
        # Ortam değişkenlerinden veya parametrelerden bilgileri alır.
        self.uri = uri or os.getenv("NEO4J_URI", "bolt://localhost:7687")
        self.user = user or os.getenv("NEO4J_USER", "neo4j")
        self.password = password or os.getenv("NEO4J_PASSWORD", "password")
        
        self.driver = None

    def connect(self):
        """Veritabanına bağlanır."""
        try:
            self.driver = GraphDatabase.driver(self.uri, auth=(self.user, self.password))
            # Test connection
            self.driver.verify_connectivity()
            logger.info("Neo4j Graph Database bağlantısı başarılı.")
        except Exception as e:
            logger.error(f"Neo4j'ye bağlanılamadı. Hata: {str(e)}")
            self.driver = None

    def close(self):
        """Bağlantıyı kapatır."""
        if self.driver:
            self.driver.close()

    def insert_review_action(self, user_id: str, product_id: str, review_data: dict) -> bool:
        """
        Kullanıcının (User) bir ürüne (Product) yaptığı yorumu ağ (Yönlü kenar) olarak ekler.
        """
        if not self.driver:
            logger.warning("Veritabanı bağlantısı yok. Metod çalıştırılmadı.")
            return False

        cypher_query = """
        MERGE (u:User {id: $user_id})
        MERGE (p:Product {id: $product_id})
        CREATE (u)-[r:WROTE {
            date: $date, 
            rating: $rating, 
            sentiment_score: $sentiment,
            is_flagged: $is_flagged
        }]->(p)
        RETURN r
        """
        
        parameters = {
            "user_id": user_id,
            "product_id": product_id,
            "date": review_data.get("date", ""),
            "rating": review_data.get("rating", 0),
            "sentiment": review_data.get("sentiment_score", 0.0),
            "is_flagged": review_data.get("is_flagged", False)
        }

        try:
            with self.driver.session() as session:
                session.run(cypher_query, parameters)
            return True
        except Exception as e:
            logger.error(f"Review düğümü eklenirken Graph hatası: {str(e)}")
            return False

    def check_swarm_behavior(self, product_id: str, time_window_hours: int = 24) -> List[Dict[str, Any]]:
        """
        Aynı ürüne aşırı kısa sürelerde benzer oranda saldırı yapan (swarm/küme) kişileri tespit eder.
        Not: Bu basitleştirilmiş bir mock sorgudur, mantığı temsil eder.
        """
        if not self.driver:
            return []

        cypher_query = """
        MATCH (u:User)-[r:WROTE]->(p:Product {id: $product_id})
        WITH u, r.date AS r_date
        // Burada gerçek tarihler arası 'duration' hesabı yapılır (Neo4j Temporal Functions)
        // Eğer kısa sürede çok fazla 5 yıldız gelmişse bu bir "Swarm" dalgasıdır.
        RETURN u.id AS bot_candidate_id, count(*) AS action_count
        LIMIT 100
        """
        
        try:
            with self.driver.session() as session:
                result = session.run(cypher_query, {"product_id": product_id})
                return [{"user_id": record["bot_candidate_id"]} for record in result]
        except Exception as e:
            logger.error(f"Kümeleme analizi sırasında hata: {str(e)}")
            return []
