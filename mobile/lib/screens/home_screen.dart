import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../utils/scraper_script.dart';
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
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
  
  // History State
  bool _isLoadingHistory = false;
  List<dynamic> _historyRecords = [];
  String? _historyError;

  // Use 10.0.2.2 for Android Emulator, 127.0.0.1 for iOS Simulator/Web
  // Android Emülatör için 10.0.2.2 kullanılır (Bilgisayarın localhost'una erişmek için)
  // iOS Simülatör veya Web için 127.0.0.1 kullanabilirsiniz.
  final String baseApiUrl = 'http://10.0.2.2:8000/api/v1'; 

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _historyRecords.isEmpty) {
        _fetchHistory();
      }
    });

    // Share Intent Listeners
    _intentDataStreamSubscription = ReceiveSharingIntent.getTextStream().listen((String value) {
      _handleSharedText(value);
    }, onError: (err) {
      debugPrint("Paylaşım dinleme hatası: $err");
    });

    ReceiveSharingIntent.getInitialText().then((String? value) {
      if (value != null && value.isNotEmpty) {
        _handleSharedText(value);
      }
    });

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            if (_isAnalyzing && _currentStep == "Sayfa yükleniyor...") {
              
              // Trendyol: Ürün sayfasındaysak /yorumlar sayfasına yönlendir
              if (url.contains('trendyol.com') && !url.contains('/yorumlar')) {
                final cleanUrl = url.split('?')[0].split('#')[0];
                final reviewsUrl = '$cleanUrl/yorumlar';
                setState(() {
                  _currentStep = "Yorumlar sayfasına geçiliyor...";
                  _progress = 0.15;
                });
                _webViewController.loadRequest(Uri.parse(reviewsUrl));
                return; // onPageFinished tekrar tetiklenecek
              }
              
              setState(() {
                _currentStep = "Veriler ayıklanıyor...";
                _progress = 0.3;
              });
              
              // Hepsiburada: Yorumlar sekmesine tıkla
              if (url.contains('hepsiburada.com')) {
                setState(() { _currentStep = "Yorumlar sekmesine geçiliyor..."; });
                await _webViewController.runJavaScript('''
                  (function() {
                    var clicked = false;
                    var allTabs = document.querySelectorAll('[role="tab"], [class*="Tab"], [class*="tab"], button, a');
                    for (var i = 0; i < allTabs.length; i++) {
                      var text = (allTabs[i].innerText || '').trim().toLowerCase();
                      if (text.indexOf('değerlendirme') !== -1 || text.indexOf('yorum') !== -1) {
                        allTabs[i].click();
                        clicked = true;
                        break;
                      }
                    }
                    if (!clicked) { window.scrollTo(0, document.body.scrollHeight * 0.6); }
                  })();
                ''');
                // Yorumların AJAX ile yüklenmesini bekle
                await Future.delayed(const Duration(seconds: 5));
              } else {
                // Trendyol yorumlar sayfası veya diğer siteler
                await Future.delayed(const Duration(seconds: 4));
              }
              
              if (!mounted || !_isAnalyzing) return;
              
              setState(() {
                _currentStep = "Yapay zeka verileri ayıklıyor...";
                _progress = 0.4;
              });
              
              try {
                final Object resultObj = await _webViewController.runJavaScriptReturningResult(scraperJsCode);
                String resultString = resultObj.toString();
                
                if (resultString.startsWith('"') && resultString.endsWith('"')) {
                  resultString = jsonDecode(resultString);
                }
                
                final Map<String, dynamic> extractedData = jsonDecode(resultString);
                _sendToBackend(url, extractedData);
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
    RegExp urlRegex = RegExp(r"https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)");
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
          _handleError("Zaman aşımı: Sayfa 30 saniye içinde yüklenemedi. Lütfen linki kontrol edin.");
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
      _errorMessage = message;
    });
  }

  Future<void> _sendToBackend(String url, Map<String, dynamic> extractedDataResult) async {
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

  void _pollStatus(String taskId) async {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final response = await http.get(Uri.parse('$baseApiUrl/scan/$taskId'));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (!mounted) {
            timer.cancel();
            return;
          }

          setState(() {
            _progress = (data['progress_percentage'] ?? 0) / 100.0;
            _currentStep = data['current_step'] ?? "Analiz sürüyor...";
          });

          if (data['status'] == 'COMPLETED') {
            timer.cancel();
            setState(() {
              _isAnalyzing = false;
              _result = data['result'];
            });
            // Refresh history if we just finished a scan
            _fetchHistory();
          } else if (data['status'] == 'FAILED') {
            timer.cancel();
             setState(() {
              _isAnalyzing = false;
              _errorMessage = data['error_message'] ?? "Bilinmeyen sunucu hatası!";
            });
          }
        }
      } catch (e) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
            _errorMessage = "Bağlantı koptu: ${e.toString()}";
          });
        }
      }
    });
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
        throw Exception("Geçmiş verisi alınamadı (Kod: ${response.statusCode})");
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
                  borderRadius: BorderRadius.circular(8)
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),

            if (_isAnalyzing) ...[
              const SizedBox(height: 24),
              CircularProgressIndicator(
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
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
            ] 
            else if (_result != null) ...[
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
                child: const Text("Yeni Tarama Yap", style: TextStyle(color: Colors.white)),
              )
            ]
            else ...[
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

  Widget _buildHistoryTab() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
    }

    if (_historyError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent.withOpacity(0.8), size: 64),
            const SizedBox(height: 16),
            Text(_historyError!, style: const TextStyle(color: Colors.redAccent)),
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
        child: Text("Henüz geçmiş tarama bulunmuyor.", style: TextStyle(color: Colors.white70)),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchHistory,
      color: Colors.greenAccent,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _historyRecords.length,
        itemBuilder: (context, index) {
          final record = _historyRecords[index];
          final double trustScore = (record['true_trust_score'] ?? 0.0).toDouble();
          final bool isDanger = trustScore < 3.0;

          return Card(
            color: Colors.white.withOpacity(0.05),
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDanger ? Colors.redAccent.withOpacity(0.5) : Colors.greenAccent.withOpacity(0.5)),
            ),
            child: ExpansionTile(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDanger ? Colors.redAccent.withOpacity(0.2) : Colors.greenAccent.withOpacity(0.2),
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
                      record['url'].toString().split('?').first, // Clean URL display
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
                      _statRow("Toplam Değerlendiren:", "${record['total_ratings']}", Colors.white70),
                      _statRow("Yorum Sayısı:", "${record['total_reviews']}", Colors.white70),
                      _statRow("Fotoğraflı Yorum:", "${record['photo_reviews_count'] ?? 0}", Colors.white70),
                      const Divider(color: Colors.white24, height: 24),
                      if ((record['suspicious_reviews'] as List).isNotEmpty)
                        _buildSuspiciousList(record['suspicious_reviews'])
                      else
                        const Text("Şüpheli yorum bulunamadı.", style: TextStyle(color: Colors.greenAccent)),
                    ],
                  ),
                )
              ],
            ),
          );
        },
      ),
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
        border: Border.all(color: isDanger ? Colors.redAccent : Colors.greenAccent, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Text("Decepta Gerçek Güven Skoru", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            trustScore.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 48, 
              fontWeight: FontWeight.bold,
              color: isDanger ? Colors.redAccent : Colors.greenAccent
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Toplam ${data['total_reviews']} yorum içerisinde ${data['bot_percentage']}% oranında ağ ihlali bulundu.",
            textAlign: TextAlign.center,
            style: TextStyle(color: isDanger ? Colors.redAccent : Colors.greenAccent),
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
          const Text("Sayfa İstatistikleri", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _statRow("Görünen Puan:", "${data['platform_score']}", Colors.white),
          _statRow("Toplam Değerlendiren:", "${data['total_ratings']}", Colors.white),
          _statRow("Toplam Yorum Sayısı:", "${data['total_reviews']}", Colors.white),
          _statRow("Fotoğraflı Yorum Sayısı:", "${data['photo_reviews_count'] ?? 0}", Colors.white),
          _statRow("Şüpheli Yorum:", "${(data['suspicious_reviews'] as List).length}", Colors.redAccent),
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
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
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
          border: Border.all(color: Colors.greenAccent.withOpacity(0.5))
        ),
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
          child: Text("Tespit Edilen İhlaller", style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        ...suspicious.map((item) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3))
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "\"${item['text']}\"",
                  style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  "🕵️ ${item['reason']}",
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}
