const String scraperJsCode = r'''
(() => {
    try {
        const url = window.location.href;
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

        // 2. HEPSİBURADA: v19
        if (isHepsiburada) {
            const candidates = [];
            const all = document.getElementsByTagName('*');
            const limit = Math.min(all.length, 1500);
            for (let i = 0; i < limit; i++) {
                const txt = all[i].innerText || "";
                if (txt.length > 1 && txt.length < 50) {
                    const m = txt.match(/\(\s*(\d+)\s*\)/);
                    if (m) candidates.push(parseInt(m[1]));
                }
            }
            if (candidates.length > 0) {
                if (!ratingsCount) ratingsCount = Math.max(...candidates);
                const revs = candidates.filter(v => v !== ratingsCount).sort((a,b) => b-a);
                if (revs.length > 0) {
                    commentCount = revs[0];
                    hbPhotoCount = revs[revs.length - 1];
                }
            }
            if (commentCount === 0 && ratingsCount > 0) commentCount = ratingsCount;
            if (ratingsCount > 0 && commentCount > ratingsCount) {
                const t = ratingsCount; ratingsCount = commentCount; commentCount = t;
            }
            return JSON.stringify({ extracted_data: { score, total_ratings: ratingsCount, total_reviews: commentCount, photo_reviews_count: hbPhotoCount, debug_source: 'MOBILE_V19' } });
        }

        return JSON.stringify({ extracted_data: { score, total_ratings: ratingsCount, total_reviews: commentCount, photo_reviews_count: 0 } });
    } catch (e) { return JSON.stringify({ error: e.message }); }
})();
''';
