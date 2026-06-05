import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../utils/scraper_script.dart';
import '../utils/hb_pagination_scripts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _urlController = TextEditingController();

  // Live Scan State
  bool _isAnalyzing = false;
  String _currentStep = "";
  double _progress = 0.0;
  String? _errorMessage;
  Map<String, dynamic>? _result;
  late final WebViewController _webViewController;
  StreamSubscription? _intentDataStreamSubscription;
  // HB Çok Sayfalı Tarama State
  Completer<void>? _navigationCompleter;
  bool _isHBMultiScanning = false;
  bool _hasStartedScan = false;
  bool _hasNavigatedToN11Reviews = false;

  // History State
  bool _isLoadingHistory = false;
  List<dynamic> _historyRecords = [];
  String? _historyError;

  // Use 10.0.2.2 for Android Emulator, 127.0.0.1 for iOS Simulator/Web
  // Android Emülatör için 10.0.2.2 kullanılır (Bilgisayarın localhost'una erişmek için)
  // iOS Simülatör veya Web için 127.0.0.1 kullanabilirsiniz.
  String baseApiUrl = 'http://10.90.11.191:8000/api/v1';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _historyRecords.isEmpty) {
        _fetchHistory();
      }
    });

    // Share Intent Listeners (receive_sharing_intent ^1.8.1)
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final sharedFile = value.first;
        if (sharedFile.path.isNotEmpty) {
          _handleSharedText(sharedFile.path);
        }
      }
    }, onError: (err) {
      debugPrint("Paylaşım dinleme hatası: $err");
    });

    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final sharedFile = value.first;
        if (sharedFile.path.isNotEmpty) {
          _handleSharedText(sharedFile.path);
        }
        ReceiveSharingIntent.instance.reset();
      }
    });

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            // ===== HB ÇOKLU SAYFA TARAMA MODU =====
            // Bu modda onPageFinished sadece navigation completer'ı tamamlar ve çıkar.
            // Kontrol _scanHBAllPagesAndSend() metodundadır.
            if (_isHBMultiScanning) {
              if (_navigationCompleter != null &&
                  !_navigationCompleter!.isCompleted) {
                _navigationCompleter!.complete();
              }
              return;
            }

            if (_isAnalyzing &&
                (_currentStep == "Sayfa yükleniyor..." ||
                    _currentStep == "Yorumlar sayfasına geçiliyor...")) {
              if (_hasStartedScan) return;

              // Trendyol: Ürün sayfasındaysak /yorumlar sayfasına yönlendir
              if (url.contains('trendyol.com') && !url.contains('/yorumlar')) {
                final cleanUrl = url.split('?')[0].split('#')[0];
                final reviewsUrl = '$cleanUrl/yorumlar';
                setState(() {
                  _currentStep = "Yorumlar sayfasına geçiliyor...";
                  _progress = 0.15;
                });
                _webViewController.loadRequest(Uri.parse(reviewsUrl));
                return;
              }


              // Hepsiburada: Ürün sayfasındaysak -yorumlari sayfasına yönlendir
              if (url.contains('hepsiburada.com') &&
                  !url.contains('-yorumlari')) {
                var cleanUrl = url.split('?')[0].split('#')[0];
                if (cleanUrl.endsWith('/')) {
                  cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
                }
                if (cleanUrl.contains('-p-') || cleanUrl.contains('-pm-')) {
                  setState(() {
                    _currentStep = "Yorumlar sayfasına geçiliyor...";
                    _progress = 0.15;
                  });
                  final reviewsUrl = '$cleanUrl-yorumlari';
                  _webViewController.loadRequest(Uri.parse(reviewsUrl));
                  return;
                }
              } else if (url.contains('hepsiburada.com') &&
                  url.contains('-yorumlari')) {
                // ===== HB YORUMLAR SAYFASI: ÇOK SAYFA TARAMA BAŞLAT =====
                if (!mounted || !_isAnalyzing) return;
                _hasStartedScan = true;
                setState(() {
                  _currentStep = "HB: Yorumlar çok sayfalı taranıyor...";
                  _progress = 0.35;
                });
                await _scanHBAllPagesAndSend(url);
                return;
              } else if (url.contains('trendyol.com')) {
                _hasStartedScan = true;
                // Trendyol: Lazy-load yorumları render etmek için sayfayı aşağı kaydır
                for (int i = 0; i < 10; i++) {
                  if (!mounted || !_isAnalyzing) break;
                  await _webViewController
                      .runJavaScript('window.scrollBy(0, 800);');
                  await Future.delayed(const Duration(milliseconds: 400));
                }
                await Future.delayed(const Duration(seconds: 1));
              } else if (url.contains('n11.com')) {
                if (!_hasNavigatedToN11Reviews && !url.contains('product-reviews') && !url.contains('yorumlar')) {
                  // Yorum tabını aktif et veya Tüm Yorumları Gör linkini bul
                  await _webViewController.runJavaScript('''
                     var reviewTab = document.querySelector('#tabReviews, .tabPanelReviews, a[href="#reviews"], [data-testid="reviews-tab"]');
                     if (reviewTab) {
                         reviewTab.scrollIntoView({ behavior: 'instant', block: 'center' });
                         setTimeout(function() { reviewTab.click(); }, 400);
                     } else {
                         window.scrollTo(0, document.body.scrollHeight * 0.4);
                     }
                   ''');
                  await Future.delayed(const Duration(seconds: 2));

                  final Object reviewsHrefObj =
                      await _webViewController.runJavaScriptReturningResult('''
                     (function() {
                         var linkEl = document.querySelector('a.product-reviews__link, a[href*="product-reviews"]');
                         if (linkEl && linkEl.getAttribute('href')) return linkEl.getAttribute('href');
                         var links = Array.from(document.querySelectorAll('a'));
                         var seeAllLink = links.find(function(el) { return el.textContent && el.textContent.includes('Tüm Yorumları Gör'); });
                         return seeAllLink ? seeAllLink.getAttribute('href') : null;
                     })();
                   ''');
                  var reviewsHref =
                      reviewsHrefObj.toString().replaceAll('"', '');
                  if (reviewsHref.isNotEmpty &&
                      reviewsHref != 'null' &&
                      reviewsHref != 'undefined') {
                    if (!reviewsHref.startsWith('http'))
                      reviewsHref = 'https://www.n11.com' + reviewsHref;
                    setState(() {
                      _currentStep = "Yorumlar sayfasına geçiliyor...";
                      _progress = 0.2;
                      _hasNavigatedToN11Reviews = true;
                    });
                    _webViewController.loadRequest(Uri.parse(reviewsHref));
                    return; // Yeni sayfa yüklenince onPageFinished tekrar tetiklenir
                  }
                }

                _hasStartedScan = true;
                // N11: Yorumların infinite scroll ile yüklenmesini sağla
                for (int i = 0; i < 12; i++) {
                  if (!mounted || !_isAnalyzing) break;
                  await _webViewController
                      .runJavaScript('window.scrollBy(0, 800);');
                  await Future.delayed(const Duration(milliseconds: 300));
                }
                await Future.delayed(const Duration(seconds: 1));
              } else {
                _hasStartedScan = true;
                // Diğer siteler: Sadece biraz bekle
                await Future.delayed(const Duration(seconds: 4));
              }

              if (!mounted || !_isAnalyzing) return;
              
              setState(() {
                _currentStep = "Veriler ayıklanıyor...";
                _progress = 0.3;
              });

              if (!mounted || !_isAnalyzing) return;
              
              setState(() {
                _currentStep = "Yapay zeka verileri ayıklıyor...";
                _progress = 0.4;
              });

              try {
                final Object resultObj = await _webViewController
                    .runJavaScriptReturningResult(scraperJsCode);
                final Map<String, dynamic> extractedData =
                    _safeDecodeMap(resultObj.toString());
                if (extractedData.isNotEmpty) {
                  _sendToBackend(url, extractedData);
                } else {
                  throw Exception(
                      "Dinamik DOM verisi boş döndü veya ayrıştırılamadı.");
                }
              } catch (e) {
                _handleError("JavaScript Hatası: $e");
              }
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (_isAnalyzing && _currentStep == "Sayfa yükleniyor...") {
              _handleError("Sayfa yüklenemedi: ${error.description}");
            }
          },
        ),
      );
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  // --- SHARE INTENT METHOD ---
  void _handleSharedText(String text) {
    RegExp urlRegex = RegExp(
        r"https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)");
    var match = urlRegex.firstMatch(text);

    if (match != null) {
      final extractedUrl = match.group(0)!;
      if (mounted) {
        setState(() {
          _urlController.text = extractedUrl;
        });
        _tabController.animateTo(0);
        Future.delayed(const Duration(milliseconds: 500), () {
          _startAnalysis();
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _urlController.text = text;
        });
        _tabController.animateTo(0);
      }
    }
  }

  // --- LIVE SCAN METHODS ---
  Future<void> _startAnalysis() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // URL validasyonu
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _handleError("Lütfen geçerli bir URL girin (https:// ile başlamalı).");
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _hasStartedScan = false;
      _hasNavigatedToN11Reviews = false;
      _errorMessage = null;
      _result = null;
      _progress = 0.1;
      _currentStep = "Sayfa yükleniyor...";
    });

    try {
      _webViewController.loadRequest(Uri.parse(url));

      // 30 saniye timeout — sayfa bu sürede yüklenmezse iptal et
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && _isAnalyzing && _currentStep == "Sayfa yükleniyor...") {
          _handleError(
              "Zaman aşımı: Sayfa 30 saniye içinde yüklenemedi. Lütfen linki kontrol edin.");
        }
      });
    } catch (e) {
      _handleError("URL yüklenemedi: $e");
    }
  }

  void _handleError(String message) {
    if (!mounted) return;
    setState(() {
      _isAnalyzing = false;
      _isHBMultiScanning = false;
      _navigationCompleter?.complete();
      _navigationCompleter = null;
      _errorMessage = message;
    });
  }

  List<dynamic> _safeDecodeList(String str) {
    try {
      String s = str;
      if (s.startsWith('"') && s.endsWith('"')) s = jsonDecode(s);
      final decoded = jsonDecode(s);
      if (decoded is List) return decoded;
    } catch (e) {
      debugPrint('[HB Scraper] Decode list hatası: $e');
    }
    return [];
  }

  Map<String, dynamic> _safeDecodeMap(String str) {
    try {
      String s = str;
      if (s.startsWith('"') && s.endsWith('"')) s = jsonDecode(s);
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (e) {
      debugPrint('[HB Scraper] Decode map hatası: $e');
    }
    return {};
  }

  // ================================================================
  // HEPSİBURADA ÇOKLU SAYFA TARAMA — background.js v10 eşdeğeri
  // ================================================================

  /// Hepsiburada yorum kartlarının DOM'da yüklenmesini bekler (max 8 saniye).
  Future<bool> _waitForReviewCards({int maxWaitSeconds = 8}) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime).inSeconds < maxWaitSeconds) {
      if (!mounted || !_isAnalyzing) return false;
      try {
        final Object countResult =
            await _webViewController.runJavaScriptReturningResult('''
          (function() {
            var allCards = document.querySelectorAll('[class*="ReviewCard"]');
            var topLevelCards = Array.from(allCards).filter(function(card) {
              return !card.parentElement?.className?.includes('ReviewCard');
            });
            return topLevelCards.length;
          })()
        ''');
        final int count = int.tryParse(countResult.toString()) ?? 0;
        if (count > 0) {
          debugPrint(
              '[HB Scanner] Yorum kartları başarıyla yüklendi: $count adet.');
          return true;
        }
      } catch (e) {
        // Hataları yoksay ve tekrar dene
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('[HB Scanner] Yorum kartları yükleme zaman aşımı.');
    return false;
  }

  /// Hepsiburada pagination (sayfalama) elemanlarının DOM'a eklenmesini bekler (max 5 saniye).
  Future<bool> _waitForPagination({int maxWaitSeconds = 5}) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime).inSeconds < maxWaitSeconds) {
      if (!mounted || !_isAnalyzing) return false;
      try {
        final Object pagResult = await _webViewController.runJavaScriptReturningResult('''
          (function() {
            const holder = document.querySelector('.paginationBarHolder, [class*="PaginationBar"]');
            const overlay = document.querySelector('.paginationOverlay');
            return !!(holder || overlay);
          })()
        ''');
        if (pagResult.toString() == 'true') {
          debugPrint('[HB Scanner] Sayfalama barı DOM\'a yüklendi.');
          return true;
        }
      } catch (e) {
        // Hataları yoksay
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    debugPrint('[HB Scanner] Sayfalama barı yükleme zaman aşımı.');
    return false;
  }

  /// WebView'ı verilen URL'e yönlendirir ve sayfa yüklenene kadar bekler.
  /// _isHBMultiScanning = true olduğunda onPageFinished bu completer'ı tamamlar.
  Future<void> _navigateAndWait(String url, {int extraDelayMs = 2500}) async {
    _navigationCompleter = Completer<void>();
    _webViewController.loadRequest(Uri.parse(url));
    await _navigationCompleter!.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {},
    );
    _navigationCompleter = null;
    await Future.delayed(Duration(milliseconds: extraDelayMs));
  }

  // _scrollHBPage artık _scrollAndScrapeHBPage içine entegre edildi (web extension ile senkronize).
  // Yine de ihtiyaç halinde tek başına scroll için kullanılabilir.
  Future<void> _scrollHBPage() async {
    await _webViewController.runJavaScript(hbScrollScript);
    await Future.delayed(const Duration(milliseconds: 1000));
  }

  /// HB mevcut sayfasındaki yorumları tarar ve biriktiricilere ekler.
  /// Web extension scrollAndAccumulateReviews ile TAM SENKRONIZE:
  /// - scroll sırasında birden fazla okuma (ReactVirtualized lazy-load için)
  /// - pageNum prefix'li photoKey (farklı sayfalardaki aynı yorumların çakışmaması için)
  /// Yeni veri eklendiyse [true], yoksa (yıldız-only sayfa) [false] döner.
  Future<bool> _scrollAndScrapeHBPage(
    Map<String, Map<String, dynamic>> allReviewsMap,
    Set<String> uniqueTexts,
    Set<String> uniquePhotoKeys,
    Set<String> allSeenSigs,
    int pageNum,
  ) async {
    bool addedAny = false;
    final seenSigsThisPage = <String>{};
    int textOrPhotoCount = 0;

    // İçerik işleme yardımcısı — web extension processStats() ile aynı
    void processReviews(List<dynamic> reviews) {
      for (final r in reviews) {
        final review = r as Map<String, dynamic>;
        final String sig = review['sig'] as String? ?? '';
        if (sig.isEmpty) continue;

        // Her sayfa için benzersiz anahtar (web extension: pageNum + '_' + sig)
        final String pageSig = '${pageNum}_$sig';
        final String photoKey = '${pageSig}_photo';

        allSeenSigs.add(sig); // Global geçiş kontrolü için ham imzayı koru

        final String text = review['text'] as String? ?? '';
        final List<dynamic> images = review['images'] as List<dynamic>? ?? [];
        final bool hasPhoto = review['hasPhoto'] as bool? ?? false;
        final bool hasText = review['hasText'] as bool? ?? false;

        if (!seenSigsThisPage.contains(sig)) {
          seenSigsThisPage.add(sig);
          if (hasText || hasPhoto) textOrPhotoCount++;
        }

        if (hasPhoto && !uniquePhotoKeys.contains(photoKey)) {
          uniquePhotoKeys.add(photoKey);
          addedAny = true;
        }
        if (hasText && !uniqueTexts.contains(pageSig)) {
          uniqueTexts.add(pageSig);
          addedAny = true;
        }
        if ((hasText || images.isNotEmpty) &&
            !allReviewsMap.containsKey(pageSig)) {
          allReviewsMap[pageSig] = {
            'text': text,
            'images': images,
          };
          addedAny = true;
        }
      }
    }

    try {
      // 1. En yukarı kaydır ve ilk kartları oku
      await _webViewController.runJavaScript('window.scrollTo(0, 0);');
      await Future.delayed(const Duration(milliseconds: 400));
      {
        final Object r0 = await _webViewController
            .runJavaScriptReturningResult(hbPageScrapeScript);
        processReviews(_safeDecodeList(r0.toString()));
      }

      // 2. Adım adım aşağı kaydır — her adımda oku (ReactVirtualized lazy-load)
      const int steps = 10;
      for (int i = 0; i < steps; i++) {
        if (!mounted || !_isAnalyzing) break;
        await _webViewController.runJavaScript('window.scrollBy(0, 750);');
        await Future.delayed(const Duration(milliseconds: 250));
        final Object rI = await _webViewController
            .runJavaScriptReturningResult(hbPageScrapeScript);
        processReviews(_safeDecodeList(rI.toString()));
      }

      // 3. En alta kaydır ve son durumu oku
      await _webViewController.runJavaScript(
          'window.scrollTo(0, document.documentElement.scrollHeight || document.body.scrollHeight);');
      await Future.delayed(const Duration(milliseconds: 300));
      {
        final Object rF = await _webViewController
            .runJavaScriptReturningResult(hbPageScrapeScript);
        processReviews(_safeDecodeList(rF.toString()));
      }

      debugPrint(
          '[HB Scraper] Sayfa $pageNum tamamlandı. TextOrPhoto: $textOrPhotoCount, Foto toplam: ${uniquePhotoKeys.length}');
      // Eğer bu sayfada hiç metin/fotoğraflı yorum yoksa yıldız-only sayfa
      return textOrPhotoCount > 0 || addedAny;
    } catch (e) {
      debugPrint('[HB Scraper] Sayfa $pageNum tarama hatası: $e');
      return false;
    }
  }

  /// Hepsiburada SPA/asenkron sayfa geçişinin gerçekleşmesini bekler.
  /// İlk yorum kartının imzasını kontrol ederek yeni içeriğin yüklendiğini doğrular.
  Future<bool> _waitForPageTransition(Set<String> allSeenSigs,
      {int maxWaitSeconds = 6}) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime).inSeconds < maxWaitSeconds) {
      if (!mounted || !_isAnalyzing) return false;
      try {
        final Object pageResult = await _webViewController
            .runJavaScriptReturningResult(hbPageScrapeScript);
        final List<dynamic> reviews = _safeDecodeList(pageResult.toString());

        if (reviews.isNotEmpty) {
          final firstReview = reviews.first as Map<String, dynamic>;
          final String sig = firstReview['sig'] as String? ?? '';

          if (sig.isNotEmpty && !allSeenSigs.contains(sig)) {
            // Sadece gerçek (tarih içeren) kartların gelmesini bekle, skeleton loader'ları geç
            final String text = firstReview['text'] as String? ?? '';
            final bool hasPhoto = firstReview['hasPhoto'] as bool? ?? false;
            // Web extension: rawText içinde Türkçe ay/gün ismi ara
            final bool hasRealContent = text.isNotEmpty || hasPhoto;
            // text veya fotoğraf varsa, gerçek kart gelmiştir
            if (hasRealContent) {
              debugPrint('[HB Scanner] Yeni sayfa yüklendi, ilk imza: $sig');
              return true;
            }
          }
        }
      } catch (e) {
        // Hataları yoksay
      }
      await Future.delayed(
          const Duration(milliseconds: 200)); // web extension: 200ms
    }
    debugPrint('[HB Scanner] Sayfa geçişi zaman aşımı.');
    return false;
  }

  /// Hepsiburada TÜM yorum sayfalarını tarar (background.js scanHepsiburadaAllPages eşdeğeri).
  /// Toplam sayfa sayısını hesaplayıp ?sayfa=N URL'leri ile sırayla iterate eder.
  Future<void> _scanHBAllPagesAndSend(String reviewsPageUrl) async {
    _isHBMultiScanning = true;
    _hasStartedScan = true; // onPageFinished'dan gelecek çakışan scan'ı engelle

    try {
      // Temiz başlangıç için URL'yi ana yorumlar sayfasına sıfırla (varsa sayfa parametresini uçur)
      final String cleanBase = reviewsPageUrl.split('?')[0].split('#')[0];
      final String currentUrl = await _webViewController.currentUrl() ?? '';
      if (currentUrl.split('?')[0].split('#')[0] != cleanBase ||
          currentUrl.contains('sayfa=')) {
        await _navigateAndWait(cleanBase, extraDelayMs: 1500);
      }

      // Sayfa 1 yorum kartlarının yüklenmesini bekle
      await _waitForReviewCards();
      
      // Sayfa 1 pagination bar'ın yüklenmesini bekle (Toplam sayfa sayısını doğru alabilmek için)
      await _waitForPagination();

      // Adım 1: Sayfa 1'den toplam sayfa ve script fotoğraf sayısını al
      await _scrollHBPage();
      final Object initResult = await _webViewController
          .runJavaScriptReturningResult(hbInitDataScript);
      final Map<String, dynamic> initData =
          _safeDecodeMap(initResult.toString());
      final int totalPages = initData['totalPages'] != null
          ? min((initData['totalPages'] as num).toInt(), 30)
          : 1;
      final int scriptPhotoCount = initData['scriptPhotoCount'] != null
          ? (initData['scriptPhotoCount'] as num).toInt()
          : 0;
      debugPrint(
          '[HB Scanner] Toplam sayfa: $totalPages, Script fotoğraf: $scriptPhotoCount');

      // Review biriktiriciler (background.js uniquePhotos, uniqueTexts, allReviewsMap eşdeğeri)
      final allReviewsMap = <String, Map<String, dynamic>>{};
      final uniqueTexts = <String>{};
      final uniquePhotoKeys = <String>{};
      final allSeenSigs = <String>{};

      // Adım 2: Sayfa 1'i tara (zaten yüklü) — scroll+çoklu okuma ile
      if (mounted)
        setState(() {
          _currentStep = 'HB: Sayfa 1/$totalPages taranıyor...';
          _progress = 0.36;
        });
      await _scrollAndScrapeHBPage(
          allReviewsMap, uniqueTexts, uniquePhotoKeys, allSeenSigs, 1);
      debugPrint(
          '[HB Scanner] Sayfa 1 tamamlandı. Metin: ${uniqueTexts.length}, Fotoğraf: ${uniquePhotoKeys.length}');

      // Adım 3: Sayfa 2..N — navigate + scroll + scrape
      for (int page = 2; page <= totalPages; page++) {
        if (!mounted || !_isAnalyzing) break;
        if (mounted) {
          setState(() {
            _currentStep = 'HB: Sayfa $page/$totalPages taranıyor...';
            _progress = 0.36 + (page / totalPages) * 0.14;
          });
        }

        await _navigateAndWait('$cleanBase?sayfa=$page', extraDelayMs: 1500);
        if (!mounted || !_isAnalyzing) break;

        // Sayfa geçişinin tamamlanmasını ve yeni kartların yüklenmesini bekle
        await _waitForPageTransition(allSeenSigs);

        // scrollAndScrapeHBPage kendi scroll + çoklu okuma işlemini yönetir
        final bool addedAny = await _scrollAndScrapeHBPage(
            allReviewsMap, uniqueTexts, uniquePhotoKeys, allSeenSigs, page);
        debugPrint(
            '[HB Scanner] Sayfa $page tamamlandı. Metin: ${uniqueTexts.length}, Fotoğraf: ${uniquePhotoKeys.length}');

        // Sadece yıldız-only sayfaya ulaştıysak (hiç metin/foto yok) erken çık
        if (!addedAny && page > 2) {
          debugPrint(
              '[HB Scanner] Sayfa $page boş (yıldız-only), tarama sonlandırılıyor.');
          break;
        }
      }

      // Adım 4: Son sayfada ana scraperı çalıştır (puan, total_ratings, debug_source için)
      final Object metaResult =
          await _webViewController.runJavaScriptReturningResult(scraperJsCode);
      final Map<String, dynamic> baseData =
          _safeDecodeMap(metaResult.toString());

      // Adım 5: Biriktirilen çok sayfalı veriyi temel veriye yaz
      final List<String> commentsList = allReviewsMap.values
          .where((r) => (r['text'] as String? ?? '').isNotEmpty)
          .map((r) => r['text'] as String)
          .toList();
      final List<Map<String, dynamic>> detailedList =
          allReviewsMap.values.toList();
      final int photoCount = uniquePhotoKeys.length;

      if (baseData['extracted_data'] != null) {
        // Çok sayfalı taranan yorumları HER ZAMAN yaz (comments boş olsa bile baseData'yı kirletme)
        if (commentsList.isNotEmpty) {
          baseData['extracted_data']['comments'] = commentsList;
          baseData['extracted_data']['detailed_reviews'] = detailedList;
        }
        baseData['extracted_data']['photo_reviews_count'] = photoCount;
        // KRITIK: scraperJsCode SON SAYFADA çalıştığı için total_reviews değeri
        // o sayfadaki kart sayısını gösterir (örn. 10), toplam değil.
        // Çok sayfalı taramada her zaman biriktirilmiş değeri kullan.
        if (uniqueTexts.isNotEmpty) {
          baseData['extracted_data']['total_reviews'] = uniqueTexts.length;
        }
        baseData['extracted_data']['debug_source'] = 'MOBILE_HB_MULTIPAGE_v3';
      }

      debugPrint(
          '[HB Scanner] Tamamlandı. Yorum: ${commentsList.length}, Fotoğraf: $photoCount');
      _isHBMultiScanning = false;
      _sendToBackend(reviewsPageUrl, baseData);
    } catch (e) {
      _isHBMultiScanning = false;
      debugPrint('[HB Scanner] Hata: $e — tek sayfa moduna düşülüyor.');
      // Fallback: tek sayfa tarama
      try {
        final Object resultObj = await _webViewController
            .runJavaScriptReturningResult(scraperJsCode);
        final Map<String, dynamic> extractedData =
            _safeDecodeMap(resultObj.toString());
        if (extractedData.isNotEmpty) {
          _sendToBackend(reviewsPageUrl, extractedData);
        } else {
          throw Exception("Dinamik DOM verisi boş döndü veya ayrıştırılamadı.");
        }
      } catch (e2) {
        if (mounted) _handleError('Tarama Hatası: $e2');
      }
    }
  }

  Future<void> _sendToBackend(
      String url, Map<String, dynamic> extractedDataResult) async {
    setState(() {
      _currentStep = "Yapay Zeka analizine gönderiliyor...";
      _progress = 0.6;
    });

    try {
      final response = await http.post(
        Uri.parse('$baseApiUrl/scan/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "url": url,
          "extracted_data": extractedDataResult['extracted_data'] ?? {},
          "html_content": extractedDataResult['html'] ?? '',
          "text_content": extractedDataResult['text'] ?? ''
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Sunucuya bağlanılamadı. Kod: ${response.statusCode}");
      }

      final data = jsonDecode(response.body);
      final taskId = data['task_id'];
      _pollStatus(taskId);
    } catch (e) {
      _handleError(e.toString().contains('Failed host lookup')
          ? "Sunucu (FastAPI) bulunamadı. Lütfen Endpoint IP'sini kontrol edin."
          : "Backend Hatası: ${e.toString()}");
    }
  }

  /// Backend task durumunu sıralı (sequential) olarak yoklar.
  /// Timer.periodic yerine while-loop kullanılarak aynı anda birden fazla
  /// HTTP isteğinin çakışması (race condition) 100% önlenir.
  Future<void> _pollStatus(String taskId) async {
    while (mounted && _isAnalyzing) {
      try {
        final response = await http.get(Uri.parse('$baseApiUrl/scan/$taskId'));

        if (!mounted || !_isAnalyzing) return;

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data['status'] == 'COMPLETED') {
            // TEK setState çağrısı — arada geçiş/flas yok
            setState(() {
              _isAnalyzing = false;
              _progress = 1.0;
              _result = data['result'];
            });
            _fetchHistory();
            return; // Polling döngüsünden çık
          } else if (data['status'] == 'FAILED') {
            setState(() {
              _isAnalyzing = false;
              _errorMessage =
                  data['error_message'] ?? "Bilinmeyen sunucu hatası!";
            });
            return; // Polling döngüsünden çık
          }

          // Devam eden işlem — sadece progress güncelle
          setState(() {
            _progress = (data['progress_percentage'] ?? 0) / 100.0;
            _currentStep = data['current_step'] ?? "Analiz sürüyor...";
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
            _errorMessage = "Bağlantı koptu: ${e.toString()}";
          });
        }
        return; // Polling döngüsünden çık
      }

      // Sonraki poll öncesi 2 saniye bekle (sıralı — önceki istek tamamlanmadan yenisi başlamaz)
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  // --- HISTORY METHODS ---
  Future<void> _fetchHistory() async {
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
    });

    try {
      final response = await http.get(Uri.parse('$baseApiUrl/history/'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _historyRecords = data is List ? data : [];
          _isLoadingHistory = false;
        });
      } else {
        throw Exception(
            "Geçmiş verisi alınamadı (Kod: ${response.statusCode})");
      }
    } catch (e) {
      setState(() {
        _isLoadingHistory = false;
        _historyError = "Hata: ${e.toString()}";
      });
    }
  }

  // --- UI BUILDING ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Decepta AI",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: "Bağlantı Ayarları",
            onPressed: () {
              final controller = TextEditingController(text: baseApiUrl);
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF0F172A),
                  title: const Text("Backend Bağlantı Ayarları",
                      style: TextStyle(color: Colors.white)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "Fiziksel cihaz testlerinde bilgisayarınızın yerel ağ IP'sini girmelisiniz.",
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "http://10.90.11.191:8000/api/v1",
                          hintStyle:
                              TextStyle(color: Colors.white.withOpacity(0.3)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.greenAccent.withOpacity(0.3)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Bilgisayarınızın IP Adresleri:",
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "• Wi-Fi: 10.90.11.191\n• Ethernet: 192.168.56.1",
                        style:
                            TextStyle(color: Colors.greenAccent, fontSize: 12),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      child: const Text("Vazgeç",
                          style: TextStyle(color: Colors.white54)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text("Kaydet"),
                      onPressed: () {
                        setState(() {
                          baseApiUrl = controller.text.trim();
                        });
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF0F172A),
                            content: Text(
                              "Sunucu adresi güncellendi: $baseApiUrl",
                              style: const TextStyle(color: Colors.greenAccent),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.greenAccent,
          labelColor: Colors.greenAccent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.radar), text: "Canlı Analiz"),
            Tab(icon: Icon(Icons.history), text: "Geçmiş Taramalar"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLiveAnalysisTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildLiveAnalysisTab() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isAnalyzing && _result == null) ...[
              const Icon(
                Icons.shield_outlined,
                size: 80,
                color: Colors.greenAccent,
              ),
              const SizedBox(height: 16),
              const Text(
                "Gerçek Dünyaya Hoşgeldin.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
            const SizedBox(height: 32),
            TextField(
              controller: _urlController,
              enabled: !_isAnalyzing,
              decoration: InputDecoration(
                hintText: "Ürün linkini yapıştır (Trendyol/HB)...",
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(20),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_isAnalyzing) ...[
              const SizedBox(height: 24),
              CircularProgressIndicator(
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                value: _progress > 0 ? _progress : null,
              ),
              const SizedBox(height: 16),
              Text(
                _currentStep,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.greenAccent, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                "%${(_progress * 100).toInt()} Tamamlandı",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 1,
                width: MediaQuery.of(context).size.width,
                child: Opacity(
                  opacity: 0.01,
                  child: WebViewWidget(controller: _webViewController),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
                label: const Text("Taramayı İptal Et", style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _isAnalyzing = false;
                    _isHBMultiScanning = false;
                    _hasStartedScan = false;
                    if (_navigationCompleter != null && !_navigationCompleter!.isCompleted) {
                      _navigationCompleter!.complete();
                    }
                    _navigationCompleter = null;
                    _errorMessage = "Tarama kullanıcı tarafından iptal edildi.";
                  });
                },
              ),
            ] else if (_result != null) ...[
              _buildResultCard(_result!),
              const SizedBox(height: 16),
              _buildStatsCard(_result!),
              const SizedBox(height: 16),
              _buildSuspiciousList(_result!['suspicious_reviews'] ?? []),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _result = null;
                    _urlController.clear();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.1),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Yeni Tarama Yap",
                    style: TextStyle(color: Colors.white)),
              )
            ] else ...[
              ElevatedButton(
                onPressed: _startAnalysis,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                ),
                child: const Text(
                  "Gerçek Skoru Bul",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _deleteHistoryItem(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseApiUrl/history/$id'));
      if (response.statusCode == 200) {
        setState(() {
          _historyRecords.removeWhere((item) => item['id'] == id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kayıt başarıyla silindi.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.black87)
        );
      }
    } catch (e) {
      debugPrint("Silme hatası: $e");
    }
  }

  Future<void> _deleteAllHistory() async {
    try {
      final response = await http.delete(Uri.parse('$baseApiUrl/history/'));
      if (response.statusCode == 200) {
        setState(() {
          _historyRecords.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tüm geçmiş temizlendi.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.black87)
        );
      }
    } catch (e) {
      debugPrint("Toplu silme hatası: $e");
    }
  }

  Widget _buildHistoryTab() {
    if (_isLoadingHistory) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.greenAccent));
    }

    if (_historyError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                color: Colors.redAccent.withOpacity(0.8), size: 64),
            const SizedBox(height: 16),
            Text(_historyError!,
                style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchHistory,
              child: const Text("Tekrar Dene"),
            )
          ],
        ),
      );
    }

    if (_historyRecords.isEmpty) {
      return const Center(
        child: Text("Henüz geçmiş tarama bulunmuyor.",
            style: TextStyle(color: Colors.white70)),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: Colors.grey[900],
                    title: const Text("Tüm Geçmişi Sil", style: TextStyle(color: Colors.white)),
                    content: const Text("Tüm geçmiş taramalar kalıcı olarak silinecek. Emin misiniz?", style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.white54))),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Sil", style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                );
                if (confirm == true) {
                  _deleteAllHistory();
                }
              },
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              label: const Text("Tümünü Temizle", style: TextStyle(color: Colors.redAccent)),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
      onRefresh: _fetchHistory,
      color: Colors.greenAccent,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _historyRecords.length,
        itemBuilder: (context, index) {
          final record = _historyRecords[index];
          final double trustScore =
              (record['true_trust_score'] ?? 0.0).toDouble();
          final bool isDanger = trustScore < 3.0;

          return Dismissible(
            key: Key(record['id']),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete, color: Colors.white, size: 32),
            ),
            onDismissed: (direction) {
              _deleteHistoryItem(record['id']);
            },
            child: Card(
              color: Colors.white.withOpacity(0.05),
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: isDanger
                        ? Colors.redAccent.withOpacity(0.5)
                        : Colors.greenAccent.withOpacity(0.5)),
              ),
              child: ExpansionTile(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDanger
                          ? Colors.redAccent.withOpacity(0.2)
                          : Colors.greenAccent.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      trustScore.toStringAsFixed(1),
                      style: TextStyle(
                        color: isDanger ? Colors.redAccent : Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      record['url']
                          .toString()
                          .split('?')
                          .first, // Clean URL display
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 46.0),
                child: Text(
                  "Platform: ${record['platform_score']} • Bot Oranı: %${record['bot_percentage']}",
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _statRow("Toplam Değerlendiren:",
                          "${record['total_ratings']}", Colors.white70),
                      _statRow("Yorum Sayısı:", "${record['total_reviews']}",
                          Colors.white70),
                      _statRow(
                          "Fotoğraflı Yorum:",
                          "${record['photo_reviews_count'] ?? 0}",
                          Colors.white70),
                      const Divider(color: Colors.white24, height: 24),
                      if ((record['suspicious_reviews'] as List).isNotEmpty)
                        _buildSuspiciousList(record['suspicious_reviews'])
                      else
                        const Text("Şüpheli yorum bulunamadı.",
                            style: TextStyle(color: Colors.greenAccent)),
                    ],
                  ),
                )
              ],
            ),
            ),
          );
        },
      ),
    ),
    ),
    ],
    );
  }

  // --- REUSABLE WIDGETS ---
  Widget _buildResultCard(Map<String, dynamic> data) {
    final double trustScore = data['true_trust_score']?.toDouble() ?? 0.0;
    final bool isDanger = trustScore < 3.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border.all(
            color: isDanger ? Colors.redAccent : Colors.greenAccent, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Text("Decepta Gerçek Güven Skoru",
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            trustScore.toStringAsFixed(1),
            style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: isDanger ? Colors.redAccent : Colors.greenAccent),
          ),
          const SizedBox(height: 16),
          Text(
            "Toplam ${data['total_reviews']} yorum içerisinde ${data['bot_percentage']}% oranında ağ ihlali bulundu.",
            textAlign: TextAlign.center,
            style: TextStyle(
                color: isDanger ? Colors.redAccent : Colors.greenAccent),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Sayfa İstatistikleri",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _statRow("Görünen Puan:", "${data['platform_score']}", Colors.white),
          _statRow("Toplam Değerlendiren:", "${data['total_ratings']}",
              Colors.white),
          _statRow(
              "Toplam Yorum Sayısı:", "${data['total_reviews']}", Colors.white),
          _statRow("Fotoğraflı Yorum Sayısı:",
              "${data['photo_reviews_count'] ?? 0}", Colors.white),
          _statRow(
              "Şüpheli Yorum:",
              "${(data['suspicious_reviews'] as List).length}",
              Colors.redAccent),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildSuspiciousList(List suspicious) {
    if (suspicious.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.greenAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.5))),
        child: const Text(
          "Şüpheli bir yorum tespit edilemedi. Ürün organik görünüyor.",
          style: TextStyle(color: Colors.greenAccent),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12.0),
          child: Text("Tespit Edilen İhlaller",
              style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ),
        ...suspicious.map((item) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "\"${item['text']}\"",
                  style: const TextStyle(
                      color: Colors.white,
                      fontStyle: FontStyle.italic,
                      fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  "🕵️ ${item['reason']}",
                  style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}
