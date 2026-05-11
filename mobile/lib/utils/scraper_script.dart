const String scraperJsCode = r'''
(() => {
    try {
        const url = window.location.href;
        const bodyText = document.body.innerText;
        const isTrendyol = url.includes('trendyol.com');
        const isHepsiburada = url.includes('hepsiburada.com');
        
        let score = 0;
        let ratingsCount = 0;
        let commentCount = 0;
        let comments = [];
        
        // 1. DOM Metadata
        if (score === 0) {
            const scoreEls = ['.pr-in-rnr-v', '[class*="RatingPointer"]', '[itemprop="ratingValue"]'];
            for (const sel of scoreEls) {
                const el = document.querySelector(sel);
                if (el) {
                    const val = parseFloat((el.getAttribute('content') || el.innerText || '').trim().replace(',', '.'));
                    if (val > 0 && val <= 5) { score = val; break; }
                }
            }
        }
        if (ratingsCount === 0) {
            const countEls = ['.rvw-cnt-tx', '.total-review-count', '[itemprop="ratingCount"]'];
            for (const sel of countEls) {
                const el = document.querySelector(sel);
                if (el) {
                    const m = el.innerText.match(/(\d[\d.]*)/);
                    if (m) { ratingsCount = parseInt(m[1].replace(/\./g, '')); break; }
                }
            }
        }

        // 2. HEPSİBURADA: KESİN AYIKLAMA (v8.4)
        if (isHepsiburada) {
            let hbPhotoCount = 0;
            let hbSuccess = false;
            
            const allElements = document.getElementsByTagName('*');
            for (let i = 0; i < allElements.length; i++) {
                const el = allElements[i];
                if (el.children.length > 0) continue;
                const txt = el.innerText.trim();
                if (!hbSuccess || commentCount === 0) {
                    const m = txt.match(/Yorum(?:lar)?\s*\((\d+)\)/i);
                    if (m) { commentCount = parseInt(m[1]); hbSuccess = true; }
                }
                if (hbPhotoCount === 0) {
                    const m = txt.match(/Foto(?:ğ|g)rafl[ıi](?:\s*Yorumlar)?\s*\((\d+)\)/i);
                    if (m) hbPhotoCount = parseInt(m[1]);
                }
            }

            if (!hbSuccess || hbPhotoCount === 0) {
                const scripts = document.querySelectorAll('script');
                for (let i = 0; i < scripts.length; i++) {
                    const txt = scripts[i].textContent || '';
                    if (txt.includes('__HB_REVIEWS_INITIAL_STATE__')) {
                        try {
                            const startIdx = txt.indexOf('{', txt.indexOf('__HB_REVIEWS_INITIAL_STATE__'));
                            if (startIdx > -1) {
                                let balance = 0, endIdx = -1;
                                for (let j = startIdx; j < txt.length; j++) {
                                    if (txt[j] === '{') balance++; else if (txt[j] === '}') balance--;
                                    if (balance === 0) { endIdx = j; break; }
                                }
                                if (endIdx > -1) {
                                    const state = JSON.parse(txt.substring(startIdx, endIdx + 1));
                                    if (!ratingsCount) ratingsCount = state.ratingSummary?.totalReviewCount || 0;
                                    if (!hbSuccess) { commentCount = state.productReviews?.totalReviewCount || 0; hbSuccess = true; }
                                    if (hbPhotoCount === 0) hbPhotoCount = state.mediaSummary?.approvedMediaReviewCount || 0;
                                }
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
                    debug_source: 'MOBILE_HB_V8.4'
                }
            };
            return JSON.stringify(result);
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
