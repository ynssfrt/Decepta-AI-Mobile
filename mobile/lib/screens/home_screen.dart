import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  
  bool _isAnalyzing = false;
  String _currentStep = "";
  double _progress = 0.0;
  String? _errorMessage;
  Map<String, dynamic>? _result;
  
  // Emulator için localhost adresi
  // Gerçek cihaz kullanılıyorsa PC'nin yerel IP'si girilmelidir (Örn: 192.168.1.5)
  // final String baseUrl = 'http://10.0.2.2:8000/api/v1/scan'; // Android Emulator
  final String baseUrl = 'http://127.0.0.1:8000/api/v1/scan'; // Web/iOS Simulator veya Windows

  Future<void> _startAnalysis() async {
    if (_urlController.text.trim().isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _result = null;
      _progress = 0;
      _currentStep = "Bağlantı Kuruluyor...";
    });

    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"url": _urlController.text.trim()}),
      );

      if (response.statusCode != 200) {
        throw Exception("Sunucuya bağlanılamadı.");
      }

      final data = jsonDecode(response.body);
      final taskId = data['task_id'];
      
      _pollStatus(taskId);

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _errorMessage = e.toString().contains('Failed host lookup') 
          ? "Sunucu (FastAPI) bulunamadı. Lütfen Endpoint IP'sini kontrol edin." 
          : "Hata: ${e.toString()}";
      });
    }
  }

  void _pollStatus(String taskId) async {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final response = await http.get(Uri.parse('$baseUrl/$taskId'));
        
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

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Decepta AI",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
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
                  hintText: "https://www.trendyol.com/...",
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
              ] 
              else if (_result != null) ...[
                _buildResultCard(),
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
      ),
    );
  }

  Widget _buildResultCard() {
    final double trustScore = _result!['true_trust_score']?.toDouble() ?? 0.0;
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
            trustScore.toString(),
            style: TextStyle(
              fontSize: 48, 
              fontWeight: FontWeight.bold,
              color: isDanger ? Colors.redAccent : Colors.greenAccent
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Yorumların %${_result!['bot_percentage']} oranı botlar tarafından üretilmiş olabilir.",
            textAlign: TextAlign.center,
            style: TextStyle(color: isDanger ? Colors.redAccent : Colors.greenAccent),
          ),
        ],
      ),
    );
  }
}
