const String scraperJsCode = r'''
(() => {
    try {
        const url = window.location.href;
        const html = document.body.innerHTML;
        const bodyText = document.body.innerText;
        const isHepsiburada = url.includes('hepsiburada.com');
        
        let score = 0, ratingsCount = 0, commentCount = 0, hbPhotoCount = 0;

        // 1. Metadata
        const scoreEls = ['.pr-in-rnr-v', '[class*="RatingPointer"]', '[itemprop="ratingValue"]'];
        for (const sel of scoreEls) {
            const el = document.querySelector(sel);
            if (el) { score = parseFloat((el.getAttribute('content') || el.innerText || '').replace(',', '.')); break; }
        }
        const countEls = ['.rvw-cnt-tx', '[itemprop="ratingCount"]', '[class*="ReviewSummary"] [class*="count"]'];
        for (const sel of countEls) {
            const el = document.querySelector(sel);
            if (el) { const m = el.innerText.match(/(\d+)/); if (m) { ratingsCount = parseInt(m[1]); break; } }
        }
        if (ratingsCount === 0) {
            const m = bodyText.match(/(\d+)\s*[Dd]eğerlendirme/);
            if (m) ratingsCount = parseInt(m[1]);
        }

        // 2. HEPSİBURADA: v13
        if (isHepsiburada) {
            let hbSuccess = false;
            const mYorum = html.match(/Yorum(?:lar)?\s*\((\d+)\)/i) || bodyText.match(/Yorum(?:lar)?\s*\((\d+)\)/i);
            if (mYorum) { commentCount = parseInt(mYorum[1]); hbSuccess = true; }
            const mFoto = html.match(/Foto(?:ğ|g)rafl[ıi](?:\s*Yorumlar)?\s*\((\d+)\)/i) || bodyText.match(/Foto(?:ğ|g)rafl[ıi](?:\s*Yorumlar)?\s*\((\d+)\)/i);
            if (mFoto) hbPhotoCount = parseInt(mFoto[1]);

            if (commentCount === 0 || hbPhotoCount === 0) {
                const scripts = document.querySelectorAll('script');
                for (const s of scripts) {
                    const txt = s.textContent || '';
                    if (txt.includes('__HB_REVIEWS_INITIAL_STATE__')) {
                        try {
                            const start = txt.indexOf('{', txt.indexOf('__HB_REVIEWS_INITIAL_STATE__'));
                            let balance = 0, end = -1;
                            for (let i = start; i < txt.length; i++) {
                                if (txt[i] === '{') balance++; else if (txt[i] === '}') balance--;
                                if (balance === 0) { end = i; break; }
                            }
                            if (end > -1) {
                                const state = JSON.parse(txt.substring(start, end + 1));
                                if (!ratingsCount) ratingsCount = state.ratingSummary?.totalReviewCount || 0;
                                if (commentCount === 0) { commentCount = state.productReviews?.totalReviewCount || 0; hbSuccess = true; }
                                if (hbPhotoCount === 0) hbPhotoCount = state.mediaSummary?.approvedMediaReviewCount || 0;
                            }
                        } catch (e) {}
                        break;
                    }
                }
            }
            if (commentCount === 0 && ratingsCount > 0) commentCount = ratingsCount;
            if (ratingsCount > 0 && commentCount > ratingsCount) commentCount = ratingsCount;
            return JSON.stringify({ extracted_data: { score, total_ratings: ratingsCount, total_reviews: commentCount, photo_reviews_count: hbPhotoCount, debug_source: 'MOBILE_V13' } });
        }

        return JSON.stringify({ extracted_data: { score, total_ratings: ratingsCount, total_reviews: commentCount, photo_reviews_count: 0 } });
    } catch (e) { return JSON.stringify({ error: e.message }); }
})();
''';
