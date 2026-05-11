const String scraperJsCode = r'''
(() => {
    try {
        const url = window.location.href;
        const bodyText = document.body.innerText;
        const isHepsiburada = url.includes('hepsiburada.com');
        
        let score = 0;
        let ratingsCount = 0;
        let commentCount = 0;

        // ========== HEPSİBURADA: ÖNCELİKLİ AYIKLAMA (v9) ==========
        if (isHepsiburada) {
            let hbPhotoCount = 0;
            let hbSuccess = false;

            const countEl = document.querySelector('[class*="ReviewSummary"] [class*="count"]') || document.querySelector('[itemprop="ratingCount"]');
            if (countEl) {
                const m = countEl.innerText.match(/(\d[\d.]*)/);
                if (m) ratingsCount = parseInt(m[1].replace(/\./g, ''));
            }
            const scoreEl = document.querySelector('[class*="RatingPointer"]') || document.querySelector('[itemprop="ratingValue"]');
            if (scoreEl) {
                score = parseFloat((scoreEl.getAttribute('content') || scoreEl.innerText || '').replace(',', '.'));
            }

            const tabs = document.querySelectorAll('button, a, span, b, .hermes-ReviewSummary-module-ratingCount');
            tabs.forEach(el => {
                const txt = el.innerText || '';
                const mYorum = txt.match(/Yorum(?:lar)?\s*\((\d+)\)/i);
                if (mYorum && (!hbSuccess || commentCount === 0)) { commentCount = parseInt(mYorum[1]); hbSuccess = true; }
                const mFoto = txt.match(/Foto(?:ğ|g)rafl[ıi](?:\s*Yorumlar)?\s*\((\d+)\)/i);
                if (mFoto && hbPhotoCount === 0) hbPhotoCount = parseInt(mFoto[1]);
            });

            if (!hbSuccess || hbPhotoCount === 0) {
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
                                if (!hbSuccess) { commentCount = state.productReviews?.totalReviewCount || 0; hbSuccess = true; }
                                if (hbPhotoCount === 0) hbPhotoCount = state.mediaSummary?.approvedMediaReviewCount || 0;
                            }
                        } catch (e) {}
                        break;
                    }
                }
            }

            if (commentCount === 0 && ratingsCount > 0) commentCount = ratingsCount;
            if (ratingsCount > 0 && commentCount > ratingsCount) commentCount = ratingsCount;

            const result = {
                extracted_data: {
                    score: score || 0,
                    total_ratings: ratingsCount || 0,
                    total_reviews: commentCount || 0,
                    photo_reviews_count: hbPhotoCount || 0,
                    debug_source: 'MOBILE_HB_V9'
                }
            };
            return JSON.stringify(result);
        }

        // Generic fallback for others
        const scoreEls = ['.pr-in-rnr-v', '[itemprop="ratingValue"]'];
        for (const sel of scoreEls) {
            const el = document.querySelector(sel);
            if (el) { score = parseFloat((el.getAttribute('content') || el.innerText || '').replace(',', '.')); break; }
        }

        const finalResult = {
            extracted_data: {
                score: score || 0,
                total_ratings: ratingsCount || 0,
                total_reviews: commentCount,
                photo_reviews_count: 0
            }
        };
        return JSON.stringify(finalResult);
    } catch (e) {
        return JSON.stringify({ error: e.message });
    }
})();
''';
