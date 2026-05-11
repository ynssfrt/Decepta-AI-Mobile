const String scraperJsCode = r'''
(() => {
    try {
        const url = window.location.href;
        const html = document.documentElement.innerHTML;
        const bodyText = document.body.innerText;
        const isHepsiburada = url.includes('hepsiburada.com');
        
        let score = 0, ratingsCount = 0, commentCount = 0, hbPhotoCount = 0;

        // 1. Metadata
        const scoreEls = ['.pr-in-rnr-v', '[class*="RatingPointer"]', '[itemprop="ratingValue"]'];
        for (const sel of scoreEls) {
            const el = document.querySelector(sel);
            if (el) { score = parseFloat((el.getAttribute('content') || el.innerText || '').replace(',', '.')); break; }
        }
        if (ratingsCount === 0) {
            const m = bodyText.match(/(\d+)\s*[Dd]eğerlendirme/);
            if (m) ratingsCount = parseInt(m[1]);
        }

        // 2. HEPSİBURADA: v14
        if (isHepsiburada) {
            const mR = html.match(/"productReviews"\s*:\s*\{\s*"totalReviewCount"\s*:\s*(\d+)/);
            if (mR) commentCount = parseInt(mR[1]);
            const mP = html.match(/"mediaSummary"\s*:\s*\{\s*"approvedMediaReviewCount"\s*:\s*(\d+)/);
            if (mP) hbPhotoCount = parseInt(mP[1]);

            if (commentCount === 0) {
                const mY = html.match(/Yorumlar\s*\((\d+)\)/i) || bodyText.match(/Yorumlar\s*\((\d+)\)/i);
                if (mY) commentCount = parseInt(mY[1]);
            }
            if (commentCount === 0 && ratingsCount > 0) commentCount = ratingsCount;
            if (ratingsCount > 0 && commentCount > ratingsCount) commentCount = ratingsCount;
            return JSON.stringify({ extracted_data: { score, total_ratings: ratingsCount, total_reviews: commentCount, photo_reviews_count: hbPhotoCount, debug_source: 'MOBILE_V14' } });
        }

        return JSON.stringify({ extracted_data: { score, total_ratings: ratingsCount, total_reviews: commentCount, photo_reviews_count: 0 } });
    } catch (e) { return JSON.stringify({ error: e.message }); }
})();
''';
