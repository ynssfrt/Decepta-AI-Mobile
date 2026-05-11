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
        const mRatings = bodyText.match(/(\d+)\s*[Dd]eğerlendirme/);
        if (mRatings) ratingsCount = parseInt(mRatings[1]);

        // 2. HEPSİBURADA: v18
        if (isHepsiburada) {
            const allCounts = [];
            const matches = html.match(/"totalReviewCount"\s*:\s*(\d+)/g);
            if (matches) {
                matches.forEach(m => {
                    const val = parseInt(m.match(/(\d+)/)[1]);
                    if (val > 0 && val < 1000000) allCounts.push(val);
                });
            }
            if (allCounts.length > 0) {
                if (!ratingsCount) ratingsCount = Math.max(...allCounts);
                const candidates = allCounts.filter(v => v !== ratingsCount).sort((a,b) => b-a);
                if (candidates.length > 0) commentCount = candidates[0];
            }
            const mP = html.match(/"approvedMediaReviewCount"\s*:\s*(\d+)/) || html.match(/"mediaCount"\s*:\s*(\d+)/);
            if (mP) hbPhotoCount = parseInt(mP[1]);

            if (commentCount === 0 && ratingsCount > 0) commentCount = ratingsCount;
            if (ratingsCount > 0 && commentCount > ratingsCount) {
                const temp = ratingsCount; ratingsCount = commentCount; commentCount = temp;
            }
            return JSON.stringify({ extracted_data: { score, total_ratings: ratingsCount, total_reviews: commentCount, photo_reviews_count: hbPhotoCount, debug_source: 'MOBILE_V18' } });
        }

        return JSON.stringify({ extracted_data: { score, total_ratings: ratingsCount, total_reviews: commentCount, photo_reviews_count: 0 } });
    } catch (e) { return JSON.stringify({ error: e.message }); }
})();
''';
