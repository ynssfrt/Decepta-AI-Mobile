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
        let debug_source = '';

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
                if (ratingsCount === 0) {
                    const totals = []; findAll(nd, 'totalRatingCount', totals, 0);
                    if (totals.length > 0) ratingsCount = parseInt(totals[0]);
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

        if (comments.length === 0) {
            const containerSelectors = ['.rnr-com-w', '.pr-rvw-crd', '[class*="review-card"]', '[class*="reviewCard"]', '.review', '[class*="hermes-ReviewCard-module"]', '[class*="ReviewCard"]'];
            for (const sel of containerSelectors) {
                const cards = document.querySelectorAll(sel);
                if (cards.length > 0) {
                    cards.forEach(el => {
                        const textSelectors = ['.rnr-com-tx', '.comment-text', '.review-comment', '.review-text', '.pr-rvw-crd-tx', '[itemprop="description"]', '[class*="review-comment"]', '[class*="ReviewCard-module"] p', 'p'];
                        let txt = "";
                        for (const tsel of textSelectors) {
                            const textEl = el.querySelector(tsel);
                            if (textEl && textEl.innerText.trim().length > 2) { txt = textEl.innerText.trim(); break; }
                        }
                        
                        const imgs = [];
                        const isReviewPhoto = (img) => {
                            const src = img.src || img.dataset?.src || '';
                            if (!src || src.startsWith('data:')) return false;
                            const excludePatterns = ['avatar', 'star', 'icon', 'svg', 'badge', 'logo', 'emoji', 'placeholder'];
                            if (excludePatterns.some(p => src.toLowerCase().includes(p))) return false;
                            const w = img.naturalWidth || img.width || 0;
                            const h = img.naturalHeight || img.height || 0;
                            if ((w > 0 && w < 40) || (h > 0 && h < 40)) return false;
                            return true;
                        };
                        el.querySelectorAll('img').forEach(img => {
                            if (isReviewPhoto(img)) {
                                const src = img.src || img.dataset?.src;
                                if (src && !imgs.includes(src)) imgs.push(src);
                            }
                        });

                        if (txt.length > 2 || imgs.length > 0) {
                            const finalTxt = txt.length > 2 ? txt : (imgs.length > 0 ? '[Sadece Görsel]' : '');
                            if (finalTxt && !comments.includes(finalTxt)) {
                                comments.push(finalTxt);
                                detailedReviews.push({ text: finalTxt, images: imgs });
                            }
                        }
                    });
                    if (comments.length > 0) break;
                }
            }
        }

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

        if (isHepsiburada && (score === 0 || ratingsCount === 0)) {
            try {
                const scripts = document.querySelectorAll('script');
                for (const script of scripts) {
                    const text = script.textContent || '';
                    if (text.includes('review_count') || text.includes('review_rate')) {
                        const rateMatch = text.match(/["']?review_rate["']?\s*[:=]\s*["']?([\d.,]+)/);
                        const countMatch = text.match(/["']?review_count["']?\s*[:=]\s*["']?(\d[\d.]*)/);
                        if (rateMatch && score === 0) {
                            const val = parseFloat(rateMatch[1].replace(',', '.'));
                            if (val > 0 && val <= 5) { score = val; }
                        }
                        if (countMatch && ratingsCount === 0) { ratingsCount = parseInt(countMatch[1].replace(/\./g, '')); }
                        break;
                    }
                }
            } catch(e) {}
        }

        if (score === 0 || ratingsCount === 0) {
            document.querySelectorAll('script[type="application/ld+json"]').forEach(script => {
                try {
                    const raw = script.textContent;
                    if (!raw) return;
                    const data = JSON.parse(raw);
                    const check = (item) => {
                        if (item && item.aggregateRating) {
                            if (!score) {
                                const val = parseFloat(item.aggregateRating.ratingValue || 0);
                                if (val > 0 && val <= 5) { score = val; }
                            }
                            if (!ratingsCount) ratingsCount = parseInt(item.aggregateRating.ratingCount || item.aggregateRating.reviewCount || 0);
                        }
                    };
                    if (Array.isArray(data)) data.forEach(check);
                    else check(data);
                } catch(e) {}
            });
        }

        if (score === 0) {
            const patterns = [/Tüm Değerlendirmeler[\s\S]{0,5}(\d[.,]?\d)/i, /(\d[.,]\d)[\s\S]{0,30}Değerlendirme/i, /(\d[.,]\d)\s*[★☆⭐·|]/, /(\d[.,]\d)\s*(?:puan|yıldız|\(|\/\s*5)/i];
            for (const pat of patterns) {
                const m = bodyText.match(pat);
                if (m) {
                    let val = parseFloat(m[1].replace(',', '.'));
                    if (val >= 1 && val <= 5.0) { score = val; break; }
                }
            }
        }
        
        if (ratingsCount === 0) {
            const ratingPatterns = [/(\d[\d.]*)\s*(?:değerlendirme|oy|rating)/i, /[Dd]eğerlendirme(?:ler)?\s+(\d[\d.]*)/];
            for (const pat of ratingPatterns) {
                const m = bodyText.match(pat);
                if (m) {
                    const raw = m[1] || m[2];
                    if (raw) { ratingsCount = parseInt(raw.replace(/\./g, '')); break; }
                }
            }
        }
        
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

        if (isHepsiburada) {
            commentCount = 0;
            let hbSuccess = false;
            
            // YÖNTEM 1: WebView içinden doğrudan window objesini oku (Mobile Webview izole değildir)
            try {
                if (window.__HB_REVIEWS_INITIAL_STATE__) {
                    var state = window.__HB_REVIEWS_INITIAL_STATE__;
                    if (state.productReviews) {
                        commentCount = parseInt(state.productReviews.totalReviewCount || 0);
                        window.__hb_photoCount = parseInt(state.productReviews.approvedMediaReviewCount || 0);
                        hbSuccess = true;
                    } else if (state.reviews && state.reviews.summary) {
                        commentCount = parseInt(state.reviews.summary.totalReviewCount || 0);
                        window.__hb_photoCount = parseInt(state.reviews.summary.approvedMediaReviewCount || 0);
                        hbSuccess = true;
                    }
                }
            } catch(e) {}
            
            // YÖNTEM 2: Hepsiburada performanstan dolayı window objesini silmişse, ham metin üzerinden regex ile oku
            let cutoff = bodyText.search(/Benzer Ürünler|Önerilenler|Bunları da beğenebilirsiniz|Müşteriler bunları da aldı/i);
            if (cutoff === -1) cutoff = bodyText.length;
            
            const filterElements = document.querySelectorAll('button, a, span, div[class*="Filter"], div[class*="filter"], div[class*="Tab"], div[class*="tab"]');
            let foundYorum = false;
            let foundFoto = false;
            
            filterElements.forEach(el => {
                const text = (el.innerText || '').trim();
                if (text.length > 5 && text.length < 40 && bodyText.indexOf(text) < cutoff) {
                    if (!foundYorum) {
                        const m = text.match(/[Yy]orum(?:lu|lar)?\s*\(?(\d[\d.]*)\)?/);
                        if (m) { commentCount = parseInt(m[1].replace(/\./g, '')); foundYorum = true; hbSuccess = true; }
                        else {
                            const m2 = text.match(/(\d[\d.]*)\s*[Yy]orum/i);
                            if (m2) { commentCount = parseInt(m2[1].replace(/\./g, '')); foundYorum = true; hbSuccess = true; }
                        }
                    }
                    if (!foundFoto) {
                        const m = text.match(/[Ff]oto(?:ğ|g)rafl[ıi]\s*(?:Yorum(?:lar)?\s*)?\(?(\d[\d.]*)\)?/);
                        if (m) { window.__hb_photoCount = parseInt(m[1].replace(/\./g, '')); foundFoto = true; }
                        else {
                            const m2 = text.match(/(\d[\d.]*)\s*(?:adet\s*)?fotoğraflı/i);
                            if (m2) { window.__hb_photoCount = parseInt(m2[1].replace(/\./g, '')); foundFoto = true; }
                        }
                    }
                }
            });

            if (!hbSuccess) {
                const scripts = document.querySelectorAll('script');
                for (let i = 0; i < scripts.length; i++) {
                    const txt = scripts[i].textContent || '';
                    if (txt.includes('__HB_REVIEWS_INITIAL_STATE__')) {
                        const stateIndex = txt.indexOf('__HB_REVIEWS_INITIAL_STATE__');
                        const relevantTxt = txt.substring(stateIndex);
                        
                        const prIndex = relevantTxt.indexOf('"productReviews"');
                        if (prIndex > -1) {
                            const prBlock = relevantTxt.substring(prIndex);
                            
                            const totalMatch = prBlock.match(/"totalReviewCount"\s*:\s*(\d+)/);
                            if (totalMatch) {
                                commentCount = parseInt(totalMatch[1]);
                                hbSuccess = true;
                            }
                            
                            if (!foundFoto) {
                                const mediaMatch = prBlock.match(/"approvedMediaReviewCount"\s*:\s*(\d+)/);
                                if (mediaMatch) {
                                    window.__hb_photoCount = parseInt(mediaMatch[1]);
                                }
                            }
                        }
                        
                        if (hbSuccess) break;
                    }
                }
            }
            
            // HEPSİBURADA İÇİN FALLBACK YOK!
            // DOM'daki yorum kartlarını veya görselleri saymak tutarsız sonuç verir.
        }
        if (commentCount === 0 && !isHepsiburada) commentCount = comments.length;

        let photoReviewsCount = 0;
        if (isHepsiburada && typeof window.__hb_photoCount !== 'undefined') {
            photoReviewsCount = window.__hb_photoCount;
        }
        if (photoReviewsCount === 0 && !isHepsiburada) {
            const photoPatterns = [
                /[Ff]oto(?:ğ|g)rafl[ıi]\s*\(?(\d[\d.]*)\)?/,
                /(\d[\d.]*)\s*(?:adet\s*)?fotoğraflı/i,
            ];
            for (const pat of photoPatterns) {
                const m = bodyText.match(pat);
                if (m) { photoReviewsCount = parseInt(m[1].replace(/\./g, '')); break; }
            }
        }

        if (photoReviewsCount === 0 && !isHepsiburada) {
            photoReviewsCount = detailedReviews.filter(r => r.images && r.images.length > 0).length;
        }

        // MANTIK KONTROLÜ: Fotoğraflı yorum, toplam sayıyı aşamaz
        const maxReasonable = Math.max(commentCount, ratingsCount);
        if (maxReasonable > 0 && photoReviewsCount > maxReasonable) {
            photoReviewsCount = Math.min(photoReviewsCount, maxReasonable);
        }

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
        return JSON.stringify({ 
            error: e.message,
            extracted_data: { score: 0, total_ratings: 0, total_reviews: 0, comments: [], detailed_reviews: [], photo_reviews_count: 0 } 
        });
    }
})();
''';
