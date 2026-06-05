// Decepta AI - Mobile Scraper v2
// Web extension content.js v8 ile senkronize
// Trendyol: /yorumlar sayfası (rating, date, author dahil)
// Hepsiburada: -yorumlari sayfası (platform CDN whitelist + HB özel sayım)
// N11: Tam destek eklendi
const String scraperJsCode = r'''
(() => {
    try {
        const url = window.location.href;
        const bodyText = document.body.innerText;
        const isTrendyol = url.includes('trendyol.com');
        const isHepsiburada = url.includes('hepsiburada.com');
        const isN11 = url.includes('n11.com');
        
        let score = 0;
        let ratingsCount = 0;
        let commentCount = 0;
        let comments = [];
        let detailedReviews = [];
        let debug_source = '';

        // ========== Platform bazlı CDN whitelist (Web extension v8 ile senkronize) ==========
        const isReviewPhoto = (img) => {
            const src = img.src || img.dataset?.src || '';
            if (!src || src.startsWith('data:')) return false;
            
            const lowerSrc = src.toLowerCase();
            
            // Platform bazlı güvenli kaynak (whitelist) kontrolü
            if (isHepsiburada) {
                if (!(lowerSrc.includes('usercontents') || lowerSrc.includes('review-images') || lowerSrc.includes('productimages') || lowerSrc.includes('hepsiburada.net/s/'))) return false;
            } else if (isTrendyol) {
                if (!(lowerSrc.includes('dsmcdn.com') || lowerSrc.includes('ty-images.com') || lowerSrc.includes('review-images') || lowerSrc.includes('usercontents'))) return false;
            } else if (isN11) {
                if (!(lowerSrc.includes('n11scdn') || lowerSrc.includes('akamaized.net') || lowerSrc.includes('n11images.com') || lowerSrc.includes('review-images'))) return false;
            }
            
            // Küçük ikonları, yıldızları, avatarları dışla
            const excludePatterns = ['avatar', 'star', 'icon', 'svg', 'badge', 'logo', 'emoji', 'placeholder', 'thumbs'];
            if (excludePatterns.some(p => lowerSrc.includes(p))) return false;
            
            const w = img.naturalWidth || img.width || 0;
            const h = img.naturalHeight || img.height || 0;
            if ((w > 0 && w < 40) || (h > 0 && h < 40)) return false;
            return true;
        };

        // ========== Yıldız puanını sayıya çevir (Trendyol yıldız elementleri) ==========
        const extractStarRating = (el) => {
            if (!el) return null;
            
            const dataRating = el.getAttribute('data-rating') || el.getAttribute('data-score');
            if (dataRating) {
                const v = parseFloat(dataRating);
                if (v >= 1 && v <= 5) return Math.round(v);
            }
            
            const ariaLabel = el.getAttribute('aria-label') || '';
            const ariaMatch = ariaLabel.match(/^(\d[.,]?\d?)/);
            if (ariaMatch) {
                const v = Math.round(parseFloat(ariaMatch[1].replace(',', '.')));
                if (v >= 1 && v <= 5) return v;
            }
            
            // Width yüzdesi (Trendyol Mobil style="width: 100%;")
            const styleNodes = [el, ...Array.from(el.querySelectorAll('*'))];
            for (const node of styleNodes) {
                const styleStr = node.getAttribute('style') || '';
                const widthMatch = styleStr.match(/width:\s*(\d+)%/i);
                if (widthMatch) {
                    const widthVal = parseInt(widthMatch[1]);
                    if (widthVal >= 20 && widthVal <= 100) return Math.round(widthVal / 20);
                }
            }
            
            // Sınıf adından puan
            for (const node of styleNodes) {
                const classStr = (typeof node.className === 'string') ? node.className : '';
                const classMatch = classStr.match(/(?:star|rating|rnr-sm)[-_]?(100|80|60|40|20|5|4|3|2|1)\b/i);
                if (classMatch) {
                    const v = parseInt(classMatch[1]);
                    if (v > 5) return Math.round(v / 20);
                    if (v >= 1 && v <= 5) return v;
                }
            }
            
            // İkon sayımı
            const filledStars = el.querySelectorAll('[class*="full"], [class*="filled"], [class*="active"], [class*="star--filled"]');
            if (filledStars.length > 1 && filledStars.length <= 5) return filledStars.length;
            
            return null;
        };

        // ========== 1. __NEXT_DATA__ (Eski Trendyol / bazı siteler) ==========
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
                        if (val > 0 && val <= 5.0) { score = val; debug_source = 'NEXT_DATA.product'; }
                        if (product.ratingCount) ratingsCount = parseInt(product.ratingCount);
                        if (!ratingsCount && product.totalRatingCount) ratingsCount = parseInt(product.totalRatingCount);
                    }
                } catch(e) {}
                
                if (score === 0) {
                    const scores = []; findAll(nd, 'ratingScore', scores, 0);
                    for (const s of scores) {
                        const val = parseFloat(s);
                        if (val > 0 && val <= 5.0) { score = val; debug_source = 'NEXT_DATA.recursive'; break; }
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
                
                // Yorum metinleri — artık rating/date/author da çekiliyor
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
                                
                                const rating = r.rate || r.rating || r.starCount || r.reviewRating || null;
                                const date = r.lastModifiedDate || r.createdDate || r.date || r.reviewDate || null;
                                const author = r.userFullName || r.userName || r.author || r.authorName || null;
                                
                                if (typeof txt === 'string' && txt.length > 0) {
                                    const cleanTxt = txt.trim();
                                    comments.push(cleanTxt);
                                    detailedReviews.push({
                                        text: cleanTxt,
                                        images: imgs,
                                        rating: rating ? parseInt(rating) : null,
                                        date: date ? String(date) : null,
                                        author: author ? String(author) : null
                                    });
                                }
                            });
                        }
                    }
                    if (comments.length > 0) break;
                }
            } catch(e) {}
        }

        // ========== 2. N11 Özel DOM Yorum Çekimi ==========
        if (comments.length === 0 && isN11) {
            try {
                const cards = document.querySelectorAll('.review-cart-wrapper__list > .review-card, .review-cart-wrapper__list > .card-wrapper, .card-wrapper.review-card.rounded');
                cards.forEach(el => {
                    const textEl = el.querySelector('.card-detail__contents');
                    const txt = textEl ? textEl.innerText.trim() : "";
                    
                    const imgs = [];
                    el.querySelectorAll('img').forEach(img => {
                        if (isReviewPhoto(img)) {
                            const src = img.src || img.dataset?.src;
                            if (src && !imgs.includes(src)) imgs.push(src);
                        }
                    });
                    
                    // N11: Tarih ve puan
                    const dateEl = el.querySelector('.card-date, .review-date, [class*="date"]');
                    const reviewDate = dateEl ? dateEl.innerText.trim() : null;
                    const ratingEl = el.querySelector('[class*="rating"], [class*="star"]');
                    const starRating = extractStarRating(ratingEl);
                    
                    if (txt.length > 0) {
                        comments.push(txt);
                        detailedReviews.push({ text: txt, images: imgs, rating: starRating, date: reviewDate, author: null });
                    } else if (imgs.length > 0) {
                        detailedReviews.push({ text: "", images: imgs, rating: starRating, date: reviewDate, author: null });
                    }
                });
            } catch(e) {}
        }

        // ========== 3. DOM'dan Genel Yorum Çekimi (Trendyol + Hepsiburada + fallback) ==========
        if (comments.length === 0) {
            const containerSelectors = [
                '.rnr-com-w',
                '.pr-rvw-crd',
                '[class*="review-card"]',
                '[class*="reviewCard"]',
                '.review',
                '#hermes-voltran-comments [class*="ReviewCard"]',
                '.paginationContentHolder [class*="ReviewCard"]',
                '[class*="ReviewList"] [class*="ReviewCard"]',
                '[class*="hermes-ReviewCard-module"]',
                '[class*="ReviewCard"]',
                '.comment',
                '.commentDetail',
                'li.comment',
                '.card-wrapper.review-card'
            ];
            
            for (const sel of containerSelectors) {
                let cards = document.querySelectorAll(sel);
                if (cards.length > 0) {
                    // İç içe kart veya alt-eleman çakışmasını engelle (parent-child de-duplication)
                    cards = Array.from(cards).filter(card => {
                        let parent = card.parentElement;
                        while (parent) {
                            if (parent.className && typeof parent.className === 'string') {
                                const clsLower = parent.className.toLowerCase();
                                if (clsLower.includes('reviewcard') || clsLower.includes('review-card')) {
                                    return false;
                                }
                            }
                            parent = parent.parentElement;
                        }
                        return true;
                    });
                    
                    cards.forEach(el => {
                        // Yorum metnini bul
                        const textSelectors = [
                            '.rnr-com-tx',
                            '.comment-text',
                            '.review-comment',
                            '.review-text',
                            '.pr-rvw-crd-tx',
                            '[itemprop="description"]',
                            '[class*="review-comment"]',
                            'span[style*="text-align"]',
                            'span:not([class])',
                            '[class*="ReviewCard-module"] p',
                            '[class*="ReviewCard"] span[style*="text-align:start"]:not([class])',
                            'span[style*="text-align:start"]:not([class])',
                            '.card-detail__contents',
                            '.commentText',
                            '.commentDetail p',
                            'p'
                        ];
                        let txt = "";
                        for (const tsel of textSelectors) {
                            const textEl = el.querySelector(tsel);
                            if (textEl && textEl.innerText.trim().length > 0) {
                                txt = textEl.innerText.trim();
                                break;
                            }
                        }
                        
                        // Görselleri bul (platform CDN filtreli)
                        const imgs = [];
                        el.querySelectorAll('img').forEach(img => {
                            if (isReviewPhoto(img)) {
                                const src = img.src || img.dataset?.src;
                                if (src && !imgs.includes(src)) imgs.push(src);
                            }
                        });

                        // ---- Yıldız puanı ----
                        const ratingContainerSelectors = [
                            '[class*="star-w"]', '[class*="Stars"]', '[class*="stars"]',
                            '[class*="rating"]', '[class*="Rating"]',
                            '.pr-rnr-smr-rnr', '[class*="rnr"]'
                        ];
                        let starRating = null;
                        for (const rsel of ratingContainerSelectors) {
                            const ratingEl = el.querySelector(rsel);
                            starRating = extractStarRating(ratingEl);
                            if (starRating) break;
                        }
                        
                        // ---- Tarih ----
                        const dateSelectors = [
                            '[class*="date"]', '[class*="Date"]', 'time',
                            '[datetime]', 'span[content]', 'meta[itemprop="datePublished"]'
                        ];
                        let reviewDate = null;
                        for (const dsel of dateSelectors) {
                            const dateEl = el.querySelector(dsel);
                            if (dateEl) {
                                reviewDate = dateEl.getAttribute('datetime') || 
                                             dateEl.getAttribute('content') ||
                                             dateEl.innerText.trim() || null;
                                if (reviewDate && reviewDate.length > 3) break;
                            }
                        }
                        
                        // ---- Yazar ----
                        const authorSelectors = [
                            '[class*="author"]', '[class*="Author"]', '[class*="userName"]',
                            '[class*="user-name"]', 'meta[content]', '[itemprop="author"]'
                        ];
                        let author = null;
                        for (const asel of authorSelectors) {
                            const authorEl = el.querySelector(asel);
                            if (authorEl) {
                                author = authorEl.getAttribute('content') || authorEl.innerText.trim() || null;
                                if (author && author.length > 1) break;
                            }
                        }

                        if (txt.length > 0) {
                            comments.push(txt);
                            detailedReviews.push({ text: txt, images: imgs, rating: starRating, date: reviewDate, author: author });
                        } else if (imgs.length > 0) {
                            detailedReviews.push({ text: "", images: imgs, rating: starRating, date: reviewDate, author: author });
                        }
                    });
                    if (comments.length > 0) break;
                }
            }
        }

        // ========== 4. DOM'dan Puan ==========
        if (score === 0) {
            const scoreEls = [
                '.pr-in-rnr-v', '.pr-rnr-p-s', '.rnr-avg-rnr-v',
                '[class*="RatingPointer"]', '[class*="ratingPointer"]',
                '[itemprop="ratingValue"]',
                '.ratingText', '.ratingCont .rating', '.proDetailArea .ratingText'
            ];
            for (const sel of scoreEls) {
                const el = document.querySelector(sel);
                if (el) {
                    const text = (el.getAttribute('content') || el.innerText || '').trim().replace(',', '.');
                    const val = parseFloat(text);
                    if (val > 0 && val <= 5) { score = val; debug_source = 'DOM:' + sel; break; }
                }
            }
        }

        // ========== 5. DOM'dan Değerlendirme Sayısı ==========
        if (ratingsCount === 0) {
            const countEls = [
                'a.reviews-summary-reviews-detail b',
                '.rvw-cnt-tx',
                '.total-review-count',
                '[class*="ReviewSummary"] [class*="count"]',
                '[itemprop="ratingCount"]',
                '[itemprop="reviewCount"]',
                '.reviewNum', '.reviewCount',
                'a[href="#reviews"] span'
            ];
            for (const sel of countEls) {
                const el = document.querySelector(sel);
                if (el) {
                    const text = el.getAttribute('content') || el.innerText || '';
                    const m = text.match(/(\d[\d.]*)/);
                    if (m) { ratingsCount = parseInt(m[1].replace(/\./g, '')); break; }
                }
            }
        }

        // ========== 6. Hepsiburada: utagData global objesi ==========
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
                            if (val > 0 && val <= 5) { score = val; debug_source = 'HB:utagData'; }
                        }
                        if (countMatch && ratingsCount === 0) {
                            ratingsCount = parseInt(countMatch[1].replace(/\./g, ''));
                        }
                        break;
                    }
                }
            } catch(e) {}
        }

        // ========== 7. JSON-LD ==========
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
                                if (val > 0 && val <= 5) { score = val; debug_source = 'JSON-LD'; }
                            }
                            if (!ratingsCount) ratingsCount = parseInt(item.aggregateRating.ratingCount || item.aggregateRating.reviewCount || 0);
                        }
                    };
                    if (Array.isArray(data)) data.forEach(check);
                    else check(data);
                } catch(e) {}
            });
        }

        // ========== 8. Regex Fallback ==========
        if (score === 0) {
            const patterns = [
                /Tüm Değerlendirmeler[\s\S]{0,5}(\d[.,]?\d)/i,
                /(\d[.,]\d)[\s\S]{0,30}Değerlendirme/i,
                /(\d[.,]\d)\s*[★☆⭐·|]/,
                /(\d[.,]\d)\s*(?:puan|yıldız|\(|\/\s*5)/i
            ];
            for (const pat of patterns) {
                const m = bodyText.match(pat);
                if (m) {
                    let val = parseFloat(m[1].replace(',', '.'));
                    if (val >= 1 && val <= 5.0) { score = val; debug_source = 'REGEX'; break; }
                }
            }
        }
        
        if (ratingsCount === 0) {
            const ratingPatterns = [
                /(\d[\d.]*)\s*(?:değerlendirme|oy|rating)/i,
                /[Dd]eğerlendirme(?:ler)?\s+(\d[\d.]*)/
            ];
            for (const pat of ratingPatterns) {
                const m = bodyText.match(pat);
                if (m) {
                    const raw = m[1] || m[2];
                    if (raw) { ratingsCount = parseInt(raw.replace(/\./g, '')); break; }
                }
            }
        }
        
        if (commentCount === 0) {
            const patterns = [
                /(\d[\d.]*)\s*[Yy]orum/,
                /[Yy]orum(?:lar)?\s*\(?(\d[\d.]*)\)?/,
                /(\d[\d.]*)\s*(?:yorum|review|comment)/i
            ];
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

        // ========== 9. Hepsiburada Özel Yorum Sayımı ==========
        if (isHepsiburada && commentCount === 0) {
            const allCards = document.querySelectorAll('[class*="ReviewCard"]');
            const cards = Array.from(allCards).filter(card => {
                return !card.parentElement?.className?.includes('ReviewCard');
            });
            let textCardCount = 0;
            cards.forEach(card => {
                const userNameEl = card.querySelector('meta[content]');
                const userName = userNameEl ? userNameEl.getAttribute('content').trim() : '';

                let reviewDate = '';
                const spanEls = card.querySelectorAll('span[content]');
                for (const span of spanEls) {
                    const contentVal = span.getAttribute('content') || '';
                    if (contentVal.includes('-') && contentVal.length === 10) {
                        reviewDate = contentVal.trim();
                        break;
                    }
                }

                if (!userName && !reviewDate) return;

                const textSelectors = [
                    '[itemprop="description"]',
                    '[class*="review-comment"]',
                    '[class*="ReviewCard-module"] p',
                    'span[style*="text-align:start"]:not([class])',
                    'p'
                ];
                let hasText = false;
                for (const sel of textSelectors) {
                    const textEl = card.querySelector(sel);
                    if (textEl && textEl.innerText.trim().length > 0) {
                        hasText = true;
                        break;
                    }
                }
                
                const h64Count = card.querySelectorAll('[height="64px"]').length;
                const w80Count = card.querySelectorAll('[width="80"]').length;
                let hasPhoto = h64Count > 0 || w80Count > 0;
                if (!hasPhoto) {
                    card.querySelectorAll('img').forEach(img => {
                        const src = img.src || img.dataset?.src || '';
                        if (src.includes('usercontents') || src.includes('review-images')) hasPhoto = true;
                    });
                }
                
                if (hasText || hasPhoto) textCardCount++;
            });
            if (textCardCount > 0) commentCount = textCardCount;
        }
        
        // N11 Özel istatistik
        if (isN11) {
            try {
                const scoreEl = document.querySelector('span.product-review-statistics-score__big');
                if (scoreEl) {
                    const val = parseFloat(scoreEl.innerText.trim());
                    if (val > 0 && val <= 5) { score = val; debug_source = 'DOM:n11-statistics-score'; }
                }
                const ratingsEl = document.querySelector('p.product-review-statistics__review-desc');
                if (ratingsEl) ratingsCount = parseInt(ratingsEl.innerText.replace(/\D/g, ''));
                const commentEl = document.querySelector('span.product-review-statistics__review-desc');
                if (commentEl) commentCount = parseInt(commentEl.innerText.replace(/\D/g, ''));
            } catch(e) {}
        }
        
        // Yorum sayısı asla değerlendirme sayısını geçemez
        if (commentCount > 0 && ratingsCount > 0 && commentCount > ratingsCount) {
            commentCount = ratingsCount;
        }
        if (commentCount === 0) commentCount = comments.length;

        // ========== 10. Fotoğraflı Yorum Sayısı ==========
        let photoReviewsCount = 0;
        
        // Yöntem A: detailedReviews içinden
        photoReviewsCount = detailedReviews.filter(r => r.images && r.images.length > 0).length;
        
        // Yöntem B: Sayfa metni regex
        if (photoReviewsCount === 0) {
            const photoPatterns = [
                /fotoğraflı\s*(?:yorum(?:lar)?|değerlendirme(?:ler)?)?\s*\(?(\d[\d.]*)\)?/i,
                /(\d[\d.]*)\s*(?:adet\s*)?fotoğraflı/i,
                /görsel(?:li)?\s*(?:yorum(?:lar)?)?\s*\(?(\d[\d.]*)\)?/i
            ];
            for (const pat of photoPatterns) {
                const m = bodyText.match(pat);
                if (m) {
                    photoReviewsCount = parseInt(m[1].replace(/\./g, ''));
                    break;
                }
            }
        }
        
        // Yöntem C: HB özel — ReactVirtualized lazy-load için script UUID tespiti
        if (photoReviewsCount === 0 && isHepsiburada) {
            try {
                const html = document.documentElement.innerHTML;
                const matches = html.match(/usercontents\/?s\/?0\/[^\s"'<>]*([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})/g) || [];
                const uniqueIds = new Set(matches.map(m => {
                    const uuidMatch = m.match(/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/);
                    return uuidMatch ? uuidMatch[0] : m;
                }));
                if (uniqueIds.size > 0) photoReviewsCount = uniqueIds.size;
            } catch(e) {}
        }
        
        // Yöntem D: Genel fallback
        if (photoReviewsCount === 0) {
            const uniqueSrcs = new Set();
            document.querySelectorAll('[class*="review"] img, [class*="Review"] img, [class*="rvw"] img, [class*="comment"] img, [class*="Comment"] img').forEach(img => {
                if (isReviewPhoto(img)) {
                    const src = img.src || '';
                    if (src) uniqueSrcs.add(src);
                }
            });
            if (uniqueSrcs.size > 0) photoReviewsCount = uniqueSrcs.size;
        }
        
        if (!debug_source) debug_source = 'MOBILE_WEBVIEW_v2';
        
        const result = {
            extracted_data: {
                score: score || 0,
                total_ratings: ratingsCount || 0,
                total_reviews: commentCount,
                comments: comments,
                detailed_reviews: detailedReviews,
                photo_reviews_count: photoReviewsCount,
                debug_source: debug_source
            },
            html: document.documentElement.outerHTML.substring(0, 50000),
            text: bodyText.substring(0, 5000)
        };
        
        return JSON.stringify(result);
        
    } catch (e) {
        return JSON.stringify({ 
            error: e.message,
            extracted_data: { score: 0, total_ratings: 0, total_reviews: 0, comments: [], detailed_reviews: [], photo_reviews_count: 0, debug_source: 'ERROR' }
        });
    }
})();
''';
