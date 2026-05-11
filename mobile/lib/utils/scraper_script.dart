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
        let detailedReviews = [];
        
        // 1. __NEXT_DATA__
        const nextDataEl = document.getElementById('__NEXT_DATA__');
        if (nextDataEl) {
            try {
                const nd = JSON.parse(nextDataEl.textContent);
                const findAll = (obj, key, found, depth) => {
                    if (!obj || typeof obj !== 'object' || depth > 12) return;
                    if (key in obj) found.push(obj[key]);
                    for (const k of Object.keys(obj)) findAll(obj[k], key, found, depth + 1);
                };
                try {
                    const product = nd?.props?.pageProps?.product;
                    if (product && product.ratingScore) {
                        const val = parseFloat(product.ratingScore);
                        if (val > 0 && val <= 5.0) score = val;
                        if (product.ratingCount) ratingsCount = parseInt(product.ratingCount);
                    }
                } catch(e) {}
                if (ratingsCount === 0) {
                    const counts = []; findAll(nd, 'ratingCount', counts, 0);
                    if (counts.length > 0) ratingsCount = parseInt(counts[0]);
                }
            } catch(e) {}
        }

        // 2. DOM Metadata
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

        // 3. HEPSİBURADA: KESİN AYIKLAMA (v8.3)
        if (isHepsiburada) {
            let hbPhotoCount = 0;
            let hbSuccess = false;
            
            const allElements = document.querySelectorAll('button, a, span, b');
            for (const el of allElements) {
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
                            const jsonMatch = txt.match(/__HB_REVIEWS_INITIAL_STATE__\s*=\s*(\{.*\})(?:;|$)/);
                            if (jsonMatch) {
                                const state = JSON.parse(jsonMatch[1]);
                                if (!ratingsCount) ratingsCount = state.ratingSummary?.totalReviewCount || 0;
                                if (!hbSuccess) { commentCount = state.productReviews?.totalReviewCount || 0; hbSuccess = true; }
                                if (hbPhotoCount === 0) hbPhotoCount = state.mediaSummary?.approvedMediaReviewCount || 0;
                            }
                        } catch (e) {}
                        break;
                    }
                }
            }

            if (ratingsCount > 0 && commentCount > ratingsCount) commentCount = ratingsCount;

            const result = {
                extracted_data: {
                    score: score || 0,
                    total_ratings: ratingsCount || 0,
                    total_reviews: commentCount || 0,
                    comments: [],
                    detailed_reviews: [],
                    photo_reviews_count: hbPhotoCount || 0,
                    debug_source: 'MOBILE_HB_V8.3'
                },
                html: document.documentElement.outerHTML.substring(0, 500),
                text: bodyText.substring(0, 500)
            };
            return JSON.stringify(result);
        }

        // 4. Fallback counts (Non-HB)
        if (commentCount === 0) {
            const m = bodyText.match(/(\d[\d.]*)\s*[Yy]orum/);
            if (m) commentCount = parseInt(m[1].replace(/\./g, ''));
        }

        const finalResult = {
            extracted_data: {
                score: score || 0,
                total_ratings: ratingsCount || 0,
                total_reviews: commentCount,
                comments: [],
                detailed_reviews: [],
                photo_reviews_count: 0,
                debug_source: 'MOBILE_GENERIC'
            }
        };
        return JSON.stringify(finalResult);
    } catch (e) {
        return JSON.stringify({ error: e.message });
    }
})();
''';
