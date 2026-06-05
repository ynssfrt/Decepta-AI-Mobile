/// Decepta AI - Hepsiburada Çok Sayfalı Tarama JS Betikleri
/// Web Extension background.js v10 ile tam senkronize

/// Sayfa 1'den toplam sayfa sayısı ve script HTML'inden fotoğraf sayısını çeker.
const String hbInitDataScript = r'''
(() => {
  // Script HTML'inden fotoğraf UUID'lerini çek (ReactVirtualized lazy-load öncesi)
  const html = document.documentElement.innerHTML;
  const matches = html.match(/usercontents\/s\/0\/\{size\}\/([a-f0-9-]+)\.jpg/g) || [];
  const uniqueIds = new Set(matches.map(m => m.split('/').pop()));
  const scriptPhotoCount = uniqueIds.size;
  
  // Toplam değerlendirme sayısını bul (sayfa hesabı için)
  let ratingsCount = 0;
  const selectors = [
    '[itemprop="ratingCount"]', '[class*="ReviewSummary"] [class*="count"]',
    '.total-review-count', '[itemprop="reviewCount"]', 'a.reviews-summary-reviews-detail b'
  ];
  for (const sel of selectors) {
    const el = document.querySelector(sel);
    if (el) {
      const text = el.getAttribute('content') || el.innerText || '';
      const m = text.match(/(\d[\d.]*)/);
      if (m) { ratingsCount = parseInt(m[1].replace(/\./g, '')); break; }
    }
  }
  // Script fallback: utagData ve customerReviewCount
  if (!ratingsCount) {
    document.querySelectorAll('script').forEach(s => {
      const t = s.textContent || '';
      if (t.includes('review_count') || t.includes('customerReviewCount')) {
        const m1 = t.match(/["']?review_count["']?\s*[:=]\s*["']?(\d+)/);
        const m2 = t.match(/"customerReviewCount"\s*:\s*(\d+)/);
        if (m1 && !ratingsCount) ratingsCount = parseInt(m1[1]);
        if (m2 && !ratingsCount) ratingsCount = parseInt(m2[1]);
      }
    });
  }
  
  // Mobile fallback regex from body text
  if (!ratingsCount) {
    const bodyText = document.body.innerText || '';
    const m = bodyText.match(/(\d[\d.]*)\s*(?:Değerlendirme|Yorum)/i);
    if (m) ratingsCount = parseInt(m[1].replace(/\./g, ''));
  }
  
  // DOM'daki pagination butonlarından gerçek sayfa sayısını al
  const holder = document.querySelector('.paginationBarHolder, [class*="PaginationBar"]');
  let maxPage = ratingsCount > 0 ? Math.ceil(ratingsCount / 10) : 1;
  if (holder) {
    holder.querySelectorAll('a, button, span, li, div').forEach(el => {
      const txt = (el.innerText || el.textContent || '').trim();
      const num = parseInt(txt);
      if (!isNaN(num) && num > 0 && num < 500 && num > maxPage) maxPage = num;
    });
  }
  document.querySelectorAll('[data-testid*="page"], [class*="PageNumber"], [class*="pageNumber"], [class*="PageHolder"]').forEach(el => {
    const txt = (el.innerText || '').trim();
    const num = parseInt(txt);
    if (!isNaN(num) && num > 0 && num < 500 && num > maxPage) maxPage = num;
  });
  
  return JSON.stringify({ totalPages: Math.min(maxPage, 30), scriptPhotoCount });
})()
''';

/// HB tek sayfa ReviewCard tarayıcı — text + images + photo flag + benzersiz imza döner.
/// Stabil sig üretimi: userName + date + text[:60] (cardText dahil edilmez — WebView lazy-load instabilitesi önlenir).
const String hbPageScrapeScript = r'''
(() => {
  const allCards = document.querySelectorAll('[class*="ReviewCard"]');
  const topLevelCards = Array.from(allCards).filter(c => !c.parentElement?.className?.includes('ReviewCard'));
  
  const reviews = [];
  topLevelCards.forEach(card => {
    // Kullanıcı adı ve tarih
    const userNameEl = card.querySelector('meta[content]');
    const userName = userNameEl ? userNameEl.getAttribute('content').trim() : '';
    let reviewDate = '';
    card.querySelectorAll('span[content]').forEach(span => {
      const v = span.getAttribute('content') || '';
      if (v.includes('-') && v.length === 10 && !reviewDate) reviewDate = v.trim();
    });
    if (!userName && !reviewDate) return;
    
    // Yorum metni
    const textSels = [
      '[itemprop="description"]', '[class*="review-comment"]',
      'span[style*="text-align:start"]:not([class])', 'p'
    ];
    let text = '';
    for (const sel of textSels) {
      const el = card.querySelector(sel);
      if (el && el.innerText.trim().length > 0) { text = el.innerText.trim(); break; }
    }
    
    // Fotoğraf tespiti
    const h64 = card.querySelectorAll('[height="64px"]').length;
    const w80 = card.querySelectorAll('[width="80"]').length;
    let hasPhoto = h64 > 0 || w80 > 0;
    const imgs = [];
    card.querySelectorAll('img').forEach(img => {
      const src = img.src || img.dataset?.src || '';
      const lSrc = src.toLowerCase();
      if (lSrc && (lSrc.includes('usercontents') || lSrc.includes('review-images') || lSrc.includes('productimages') || lSrc.includes('hepsiburada.net/s/'))) {
        hasPhoto = true;
        if (!imgs.includes(src)) imgs.push(src);
      }
    });
    
    // Stabil imza: userName + date + text[:60] (cardText yok — scroll arası değişim riski yok)
    const sig = (userName + '_' + reviewDate + '_' + text.substring(0, 60))
      .replace(/\s+/g, '_')
      .replace(/[^\w\u00C0-\u017E_-]/g, '');
    
    if (!sig) return;
    
    reviews.push({ text, images: imgs, hasPhoto, hasText: text.length > 0, sig });
  });
  
  return JSON.stringify(reviews);
})()
''';

/// HB sayfasını yavaşça scroll eder (ReactVirtualized lazy-load tetiklemek için).
/// background.js scrollAndAccumulateReviews ile senkronize.
const String hbScrollScript = r'''
(async () => {
  const steps = 10;
  for (let i = 0; i < steps; i++) {
    window.scrollBy(0, 750);
    await new Promise(r => setTimeout(r, 250));
  }
  window.scrollTo(0, document.documentElement.scrollHeight || document.body.scrollHeight);
  await new Promise(r => setTimeout(r, 500));
})()
''';
