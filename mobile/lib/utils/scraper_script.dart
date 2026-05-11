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
                        if (val > 0 && val <= 5.0) { score = val; }
                        if (product.ratingCount) ratingsCount = parseInt(product.ratingCount);
                        if (!ratingsCount && product.totalRatingCount) ratingsCount = parseInt(product.totalRatingCount);
                    }
                } catch(e) {}
                
                if (score === 0) {
                    const scores = []; findAll(nd, 'ratingScore', scores, 0);
                    for (const s of scores) {
                        const val = parseFloat(s);
                        if (val > 0 && val <= 5.0) { score = val; break; }
                    }
                }
                if (ratingsCount === 0) {
                    const counts = []; findAll(nd, 'ratingCount', counts, 0);
                    if (counts.length > 0) ratingsCount = parseInt(counts[0]);
                }
                
                const reviewKeys = ['productReviews', 'reviews', 'userReviews'];
                for (const key of reviewKeys) {
                    const arrs = []; findAll(nd, key, arrs, 0);
                    for (const arr of arrs) {
                        if (Array.isArray(arr)) {
                            arr.forEach(r => {
                                const txt = r.comment || r.text || r.reviewText || r.body || r.content || '';
                                const imgs = [];
                                if (r.mediaUrls) {
                                    r.mediaUrls.forEach(m => { if (m.url) imgs.push(m.url); else if (typeof m === 'string') imgs.push(m); });
                                } else if (r.images) {
                                    r.images.forEach(img => { if (img.url) imgs.push(img.url); else if (typeof img === 'string') imgs.push(img); });
                                }
                                if (typeof txt === 'string' && txt.length > 2) {
                                    const cleanTxt = txt.trim();
                                    if (!comments.includes(cleanTxt)) {
                                        comments.push(cleanTxt);
                                        detailedReviews.push({ text: cleanTxt, images: imgs });
                                    }
                                }
                            });
                        }
                    }
                    if (comments.length > 0) break;
                }
            } catch(e) {}
        }

        // 2. DOM Metadata (Rating & Count)
        if (score === 0) {
            const scoreEls = ['.pr-in-rnr-v', '.pr-rnr-p-s', '.rnr-avg-rnr-v', '[class*="RatingPointer"]', '[class*="ratingPointer"]', '[itemprop="ratingValue"]'];
            for (const sel of scoreEls) {
                const el = document.querySelector(sel);
                if (el) {
                    const text = (el.getAttribute('content') || el.innerText || '').trim().replace(',', '.');
                    const val = parseFloat(text);
                    if (val > 0 && val <= 5) { score = val; break; }
                }
            }
        }
        if (ratingsCount === 0) {
            const countEls = ['a.reviews-summary-reviews-detail b', '.rvw-cnt-tx', '.total-review-count', '[class*="ReviewSummary"] [class*="count"]', '[itemprop="ratingCount"]', '[itemprop="reviewCount"]'];
            for (const sel of countEls) {
                const el = document.querySelector(sel);
                if (el) {
                    const text = el.getAttribute('content') || el.innerText || '';
                    const m = text.match(/(\d[\d.]*)/);
                    if (m) { ratingsCount = parseInt(m[1].replace(/\./g, '')); break; }
                }
            }
        }

        // 3. HEPSİBURADA: ÖZEL AYIKLAMA (v8)
        if (isHepsiburada) {
            commentCount = 0;
            let hbPhotoCount = 0;
            let hbSuccess = false;

            const scripts = document.querySelectorAll('script');
            for (let i = 0; i < scripts.length; i++) {
                const txt = scripts[i].textContent || '';
                if (txt.includes('__HB_REVIEWS_INITIAL_STATE__')) {
                    try {
                        const jsonMatch = txt.match(/__HB_REVIEWS_INITIAL_STATE__\s*=\s*(\{[\s\S]*?\});/);
                        if (jsonMatch) {
                            const state = JSON.parse(jsonMatch[1]);
                            if (state.ratingSummary && state.ratingSummary.totalReviewCount) {
                                ratingsCount = parseInt(state.ratingSummary.totalReviewCount);
                            }
                            if (state.productReviews && state.productReviews.totalReviewCount) {
                                commentCount = parseInt(state.productReviews.totalReviewCount);
                                hbSuccess = true;
                            }
                            if (state.mediaSummary && state.mediaSummary.approvedMediaReviewCount) {
                                hbPhotoCount = parseInt(state.mediaSummary.approvedMediaReviewCount);
                            } else if (state.productReviews && state.productReviews.mediaCount) {
                                hbPhotoCount = parseInt(state.productReviews.mediaCount);
                            }
                        }
                    } catch (e) {
                        const prMatch = txt.match(/"productReviews"\s*:\s*\{[^}]*?"totalReviewCount"\s*:\s*(\d+)/);
                        if (prMatch) { commentCount = parseInt(prMatch[1]); hbSuccess = true; }
                        const mediaMatch = txt.match(/"approvedMediaReviewCount"\s*:\s*(\d+)/) || txt.match(/"mediaCount"\s*:\s*(\d+)/);
                        if (mediaMatch) hbPhotoCount = parseInt(mediaMatch[1]);
                    }
                    break;
                }
            }

            if (!hbSuccess || commentCount === 0) {
                const pagText = bodyText.match(/(\d+)\s*-\s*(\d+)\s*\/\s*(\d+)/) || bodyText.match(/toplam\s*(\d+)\s*yorum/i);
                if (pagText) {
                    const val = parseInt(pagText[3] || pagText[1]);
                    if (val > 0 && val < ratingsCount) {
                        commentCount = val;
                        hbSuccess = true;
                    }
                }
            }

            if (hbPhotoCount === 0) {
                const galleryImgs = document.querySelectorAll('[class*="ImageGallery"] img, [class*="media-gallery"] img, [class*="review-image"] img');
                const photoSet = new Set();
                galleryImgs.forEach(img => {
                    const src = img.src || '';
                    if (src && !src.includes('avatar') && !src.includes('star') && (img.width > 40 || img.naturalWidth > 40)) { photoSet.add(src); }
                });
                if (photoSet.size > 0) hbPhotoCount = photoSet.size;
            }
            if (hbPhotoCount > 0) window.__hb_photoCount = hbPhotoCount;
        }

        // 4. Fallback counts
        if (commentCount === 0) {
            const patterns = [/(\d[\d.]*)\s*[Yy]orum/, /[Yy]orum(?:lar)?\s*\(?(\d[\d.]*)\)?/, /(\d[\d.]*)\s*(?:yorum|review|comment)/i];
            for (const pat of patterns) {
                const m = bodyText.match(pat);
                if (m) {
                    const raw = m[1] || m[2];
                    if (raw) {
                        const val = parseInt(raw.replace(/\./g, ''));
                        if (val > 0 && val !== ratingsCount) { commentCount = val; break; }
                    }
                }
            }
        }
        if (commentCount === 0 && !isHepsiburada) commentCount = comments.length;

        let photoReviewsCount = 0;
        if (isHepsiburada && typeof window.__hb_photoCount !== 'undefined') {
            photoReviewsCount = window.__hb_photoCount;
        } else {
            const photoPatterns = [/[Ff]oto(?:ğ|g)rafl[ıi]\s*\(?(\d[\d.]*)\)?/, /(\d[\d.]*)\s*(?:adet\s*)?fotoğraflı/i];
            for (const pat of photoPatterns) {
                const m = bodyText.match(pat);
                if (m) { photoReviewsCount = parseInt(m[1].replace(/\./g, '')); break; }
            }
            if (photoReviewsCount === 0) {
                photoReviewsCount = detailedReviews.filter(r => r.images && r.images.length > 0).length;
            }
        }

        // MANTIK KONTROLÜ
        const maxReasonable = Math.max(commentCount, ratingsCount);
        if (maxReasonable > 0 && photoReviewsCount > maxReasonable) photoReviewsCount = maxReasonable;

        const result = {
            extracted_data: {
                score: score || 0,
                total_ratings: ratingsCount || 0,
                total_reviews: commentCount,
                comments: comments,
                detailed_reviews: detailedReviews,
                photo_reviews_count: photoReviewsCount,
                debug_source: 'MOBILE_WEBVIEW'
            },
            html: document.documentElement.outerHTML.substring(0, 1000), 
            text: bodyText.substring(0, 1000)
        };
        return JSON.stringify(result);
    } catch (e) {
        return JSON.stringify({ error: e.message, extracted_data: { score: 0, total_ratings: 0, total_reviews: 0, comments: [], detailed_reviews: [], photo_reviews_count: 0 } });
    }
})();
''';
