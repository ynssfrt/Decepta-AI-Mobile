import unittest
from src.preprocessing.text_cleaner import clean_text, calculate_text_complexity

class TestAIPipeline(unittest.TestCase):
    
    def test_text_cleaning(self):
        # HTML temizleme testi
        raw_html = "<p>Harika bir ürün!</p><br>"
        self.assertEqual(clean_text(raw_html), "harika bir ürün!")
        
        # Tekrarlayan harf testi
        spam_text = "Mükemmelll ve harikaaaa"
        # 3'den fazla olanları 2'ye düşürüyoruz -> "mükemmell ve harikaa"
        self.assertEqual(clean_text(spam_text), "mükemmell ve harikaa")
        
        # Link temizleme testi
        link_text = "Bu ürünü http://spam.com adresinden al"
        self.assertEqual(clean_text(link_text).strip(), "bu ürünü adresinden al")

    def test_complexity(self):
        text = "Bu ürün çok iyi deneme yapıyorum"
        res = calculate_text_complexity(text)
        self.assertEqual(res["word_count"], 6)
        self.assertTrue(res["char_count"] > 20)

if __name__ == '__main__':
    unittest.main()
