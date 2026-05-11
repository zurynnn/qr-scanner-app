import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String BASE_URL = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'https://ml-url-api.onrender.com',
);

// Design System Constants
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppColors {
  static const Color background = Color(0xFF0D0D1A);
  static const Color surface = Color(0xFF1A1A2E);
  static const Color card = Color(0xFF1E1E2E);
  static const Color primary = Colors.deepPurple;
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(fontSize: 16, height: 1.5),
          bodyMedium: TextStyle(fontSize: 14, height: 1.4),
          labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        fontFamily: 'Poppins', // Add custom font
      ),
      home: const SplashScreen(), // ← Start here
    );
  }
}

// HISTORY HELPER — save/load from device
class ScanHistoryHelper {
  static const String _key = 'scan_history';

  // Load all history entries from device storage
  static Future<List<Map<String, dynamic>>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList(_key) ?? [];
    return raw.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  // Save a new scan entry to device storage
  static Future<void> saveEntry(String url, String result,  {bool isBlocked = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList(_key) ?? [];

    final entry = jsonEncode({
      'url': url,
      'result': result,
      'isBlocked': isBlocked,
      'time': DateTime.now().toIso8601String(),
    });

    // Add newest entry at the top
    raw.insert(0, entry);

    // Keep only last 50 entries
    if (raw.length > 50) raw.removeLast();

    await prefs.setStringList(_key, raw);
  }

  // Clear all history
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

// BLOCKED URLS HELPER — blocklist
class BlockedUrlsHelper {
  static const String _blockedKey = 'blocked_urls';
  
  static Future<void> addToBlocklist(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> blocked = prefs.getStringList(_blockedKey) ?? [];
    if (!blocked.contains(url)) {
      blocked.add(url);
      await prefs.setStringList(_blockedKey, blocked);
    }
  }
  
  static Future<bool> isBlocked(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> blocked = prefs.getStringList(_blockedKey) ?? [];
    return blocked.contains(url);
  }
  
  static Future<List<String>> getBlockedUrls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_blockedKey) ?? [];
  }
  
  static Future<void> removeFromBlocklist(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> blocked = prefs.getStringList(_blockedKey) ?? [];
    blocked.remove(url);
    await prefs.setStringList(_blockedKey, blocked);
  }

  static Future<void> updateHistoryAfterUnblock(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList('scan_history') ?? [];

    final updated = raw.map((e) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      if (map['url'] == url) {
        map['isBlocked'] = false;

        // Restore original status
        if (map['result'] == 'Blocked') {
          map['result'] = 'Malicious';
        }
      }
      
      return jsonEncode(map);
    }).toList();

    await prefs.setStringList('scan_history', updated);
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();

    // Navigate after 2.5 seconds
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const QRScannerScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha:0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.deepPurple.withValues(alpha:0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner,
                    size: 72,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const Text(
                  'Quishing Detector',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'QR Phishing Scanner',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha:0.5),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.deepPurple.withValues(alpha:0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Central configuration for backend API endpoints
class ApiConfig {
  static Uri get predictUri => Uri.parse('$BASE_URL/predict');
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  String? scannedResult;
  bool isAnalyzing = false;
  bool isProcessingPayment = false;
  DateTime? lastScanTime;
  final MobileScannerController cameraController = MobileScannerController();

  void _onScanSuccess() {
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  // Detects payment QR codes
  bool _isPaymentQR(String raw) {
    if (raw.startsWith('000201')) return true;
    if (raw.startsWith('00020') && raw.length > 20 && !raw.startsWith('http')) return true;
    if (RegExp(r'^\d{10,}').hasMatch(raw)) return true;
    return false;
  }

    // Validates URL format and blocks unsafe schemes
    // Prevents execution of malicious or non-HTTP URLs
    bool _isSafeUrl(String url) {
      final trimmed = url.trim().toLowerCase();
      
      // Block dangerous schemes
      const dangerous = ['javascript:', 'data:', 'vbscript:', 'file:', 'content:'];
      for (final scheme in dangerous) {
        if (trimmed.startsWith(scheme)) return false;
      }
      
      // Must be http or https
      return trimmed.startsWith('http://') || trimmed.startsWith('https://');
    }

    String normalizeDomain(String url) {
      try {
        String domain = Uri.parse(url).host.toLowerCase();
        return domain.startsWith('www.') ? domain.substring(4) : domain;
      } catch (e) {
        return url.toLowerCase();
      }
    }

  Future<void> _analyzeUrl(String url) async {
    if (!_isSafeUrl(url)) {
      _showErrorSnackBar('Invalid or unsafe URL format.');
      return;
    }
    
      // Check if URL is already blocked
    final domain = normalizeDomain(url);  
    if (await BlockedUrlsHelper.isBlocked(domain)) {
      _showErrorSnackBar('This URL has been blocked. Cannot analyze again.');
      return;
    }

    setState(() => isAnalyzing = true);

    try {
      final response = await http
          .post(
            ApiConfig.predictUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'url': url}),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String result = data['result'];
        final String finalUrl = data['final_url'] ?? url;

        if (result == 'Invalid URL') {
          _showErrorSnackBar('This QR code does not contain a valid URL.');
          return;
        }

        await ScanHistoryHelper.saveEntry(url, result, isBlocked: false);
        _showResultSheet(url, finalUrl, result);
      } else {
        _showErrorSnackBar('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('TimeoutException')
            ? 'Request timed out. Server may be slow, try again.'
            : 'Could not reach server. Check your connection.';
        _showRetryDialog(url, msg);
      }
    } finally {
      if (mounted) setState(() => isAnalyzing = false);
    }
  }

  Future<void> _blockAndDismiss(String url) async {
  // Add to blocklist
  final domain = normalizeDomain(url);
  await BlockedUrlsHelper.addToBlocklist(domain);
  
  //Save to history with blocked status
  await ScanHistoryHelper.saveEntry(
    url,
    'Malicious',   // keep original result
    isBlocked: true,
  );

  // Show confirmation
  _showErrorSnackBar('⚠️ URL blocked.');
  
  // Close the bottom sheet
  if (mounted) {
   Navigator.pop(context);
  }
  // Clear the scanned result
  setState(() => scannedResult = null);
  }

  Future<void> _scanFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image == null) return;

    try {
      final result = await MobileScannerController().analyzeImage(image.path);
      if (!mounted) return;

      if (result == null || result.barcodes.isEmpty) {
        _showErrorSnackBar('No QR code found in this image.');
        return;
      }

      final raw = result.barcodes.first.rawValue;
      if (raw == null) {
        _showErrorSnackBar('Could not read QR code from image.');
        return;
      }

      if (_isPaymentQR(raw)) {
        _showPaymentQRDialog();
        return;
      }

      setState(() => scannedResult = raw);
      _onScanSuccess();
    } catch (e) {
      _showErrorSnackBar('Error reading image QR code.');
    }
  }

  void _showResultSheet(String originalUrl, String finalUrl, String result) {
    final bool isMalicious = result == 'Malicious';
    final bool wasShortened = originalUrl != finalUrl;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ResultSheet(
        url: finalUrl,
        originalUrl: wasShortened ? originalUrl : null,
        isMalicious: isMalicious,
        onClose: () {
          Navigator.pop(context);
          setState(() => scannedResult = null);
        },
        onBlock: isMalicious ? () => _blockAndDismiss(finalUrl) : null,
        onOpen: isMalicious ? null : () async {
                Navigator.pop(context);
                final uri = Uri.tryParse(finalUrl);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                setState(() => scannedResult = null);
              },
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[800],
      ),
    );
  }

  void _showPaymentQRDialog() {
    setState(() {
      isProcessingPayment = true;
    });
    
    HapticFeedback.heavyImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha:0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.payment,
                color: Colors.orange,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Payment QR Code',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This is a payment QR code, not a URL.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please use your banking app to scan this code.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha:0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    isProcessingPayment = false;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).then((_) {
      setState(() {
        isProcessingPayment = false;
      });
    });
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text(
        'Quishing Detector',
        style: TextStyle(
          fontSize: 18,  // Smaller font
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Colors.white,  // Make sure text is white
        ),
      ),
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.deepPurple,
      actions: [
        IconButton(
          icon: const Icon(Icons.history, color: Colors.white),
          tooltip: 'Scan History',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const HistoryScreen(),
              ),
            );
          },
        ),
      ],
    ),
    extendBodyBehindAppBar: true,
    body: Stack(
      children: [
        // Camera feed
        MobileScanner(
          controller: cameraController,
          onDetect: (capture) {
            final now = DateTime.now();

            if (lastScanTime != null &&
                now.difference(lastScanTime!) < const Duration(seconds: 2)) {
              return; // Ignore spam scans
            }

            if (scannedResult != null || isAnalyzing) return;

            for (final barcode in capture.barcodes) {
              final raw = barcode.rawValue;
              if (raw != null) {
                lastScanTime = now;

                if (_isPaymentQR(raw)) {
                  if (!isProcessingPayment) {
                    _showPaymentQRDialog();
                  }
                  return;
                }

                setState(() => scannedResult = raw);
                _onScanSuccess();
                break;
              }
            }
          },
          
        ),

        _buildDarkOverlay(),
        
        // Scanner corners
        _buildScannerOverlay(),
        
        // Scan guide text
        _buildScanGuideText(),
        
        // Control buttons
        Positioned(
          bottom: 120,  
          left: 0,
          right: 0,
          child: _buildFlashButton(),
        ),
        
        // Gallery text button
        Positioned(
          bottom: 60,
          left: 0,
          right: 0,
          child: _buildGalleryButton(),
        ),
        
        // Result panel (when URL is scanned)
        if (scannedResult != null && !isAnalyzing) _buildResultPanel(),
        
        // Loading overlay (when analyzing)
        if (isAnalyzing) _buildLoadingOverlay(),
      ],
    ),
  );
}

Widget _buildScanGuideText() {
  return Positioned(
    bottom: 200,
    left: 0,
    right: 0,
    child: Center(
      child: const Text(
        'Place QR code in the center',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 13,
        ),
      ),
    ),
  );
}

Widget _buildFlashButton() {
  return Center(
    child: Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha:0.6),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: const Icon(Icons.flash_on, color: Colors.white, size: 28),
        onPressed: () => cameraController.toggleTorch(),
        tooltip: 'Toggle Torch',
        iconSize: 28,
      ),
    ),
  );
}

Widget _buildGalleryButton() {
  return Center(
    child: TextButton.icon(
      onPressed: _scanFromGallery,
      icon: const Icon(Icons.photo_library, color: Colors.white70, size: 20),
      label: const Text(
        'Scan from Gallery',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha:0.6),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    ),
  );
}

  // NEW: Dark overlay outside the scanning area
  Widget _buildDarkOverlay() {
    return CustomPaint(
      painter: ScannerOverlayPainter(),
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return Center(
      child: Container(
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha:0.5),
            width: 2,
          ),
        ),
        child: CustomPaint(
          painter: ScannerCornersPainter(),
        ),
      ),
    );
  }

  Widget _buildResultPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.link, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Scanned URL',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => scannedResult = null),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.deepPurple.withValues(alpha:0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      scannedResult!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: scannedResult!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('URL copied to clipboard!'),
                          duration: Duration(seconds: 2),
                          backgroundColor: Colors.deepPurple,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, color: Colors.white54, size: 18),
                    tooltip: 'Copy URL',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _analyzeUrl(scannedResult!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.security, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Analyze for Quishing',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRetryDialog(String url, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Connection Error',
            style: TextStyle(color: Colors.white)),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _analyzeUrl(url);
            },
            child: const Text('Retry',
                style: TextStyle(color: Colors.deepPurple)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShimmerLoading(
              child: CircularProgressIndicator(color: Colors.deepPurple),
            ),
            SizedBox(height: AppSpacing.md),
            Text(
              'Analyzing URL...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 3. HISTORY SCREEN ← NEW
// ─────────────────────────────────────────────
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await ScanHistoryHelper.loadHistory();
      setState(() {
        _history = history;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _clearHistory() async {
    // Show confirmation dialog before clearing
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Clear History',
            style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete all scan history?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ScanHistoryHelper.clearHistory();
      setState(() => _history = []);
    }
  }

  // Format timestamp to readable string
  String _formatTime(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text(
          'Scan History',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white70),
              tooltip: 'Clear History',
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final entry = _history[index];
                    final isMalicious = entry['result'] == 'Malicious';
                    return _buildHistoryCard(entry, isMalicious);
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: Colors.white.withValues(alpha:0.3)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No scan history yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha:0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Scanned URLs will appear here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha:0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> entry, bool isMalicious) {
    // Check if this entry is blocked
    final isBlocked = entry['isBlocked'] as bool? ?? false;
    
    // Determine color and icon based on status
    Color color;
    IconData icon;
    String statusText;
    
    if (isBlocked) {
      color = Colors.orange;
      icon = Icons.block;
      statusText = 'Blocked';
    } else if (isMalicious) {
      color = Colors.red;
      icon = Icons.warning_rounded;
      statusText = 'Malicious';
    } else {
      color = Colors.green;
      icon = Icons.verified_rounded;
      statusText = 'Safe';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha:0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          // URL and details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['url'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha:0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusText,  // ← Now shows "Blocked", "Malicious", or "Safe"
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(entry['time'] ?? ''),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha:0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Add unblock button for blocked entries
          if (isBlocked)
            IconButton(
              onPressed: () => _unblockFromHistory(entry['url']!),
              icon: const Icon(Icons.delete_outline, color: Colors.white70, size: 20),
              tooltip: 'Unblock',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  // Add this method to unblock from history
  Future<void> _unblockFromHistory(String url) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Unblock URL', style: TextStyle(color: Colors.white)),
        content: Text('Unblock $url?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unblock', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final domain = Uri.parse(url).host.toLowerCase();

      await BlockedUrlsHelper.removeFromBlocklist(domain);
      await BlockedUrlsHelper.updateHistoryAfterUnblock(url);
      
      // Update the history entry to remove blocked status
      // Reload history to refresh the display
      _loadHistory();

      if (mounted) {  
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL unblocked'), backgroundColor: Colors.green),
        );
      }
    }
  }  
}

// ─────────────────────────────────────────────
// 4. RESULT BOTTOM SHEET WIDGET
// ─────────────────────────────────────────────
class _ResultSheet extends StatelessWidget {
  final String url;
  final String? originalUrl;
  final bool isMalicious;
  final VoidCallback onClose;
  final VoidCallback? onBlock;
  final VoidCallback? onOpen;

  const _ResultSheet({
    required this.url,
    this.originalUrl,
    required this.isMalicious,
    required this.onClose,
    this.onBlock,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final color = isMalicious ? Colors.red : Colors.green;
    final icon = isMalicious ? Icons.warning_rounded : Icons.verified_rounded;
    final title = isMalicious ? 'Malicious QR Detected!' : 'QR Looks Safe';
    final subtitle = isMalicious
        ? 'This URL shows signs of phishing. Do not open it.'
        : 'No phishing indicators detected. You may proceed.';

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Icon badge
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha:0.4), width: 2),
            ),
            child: Icon(icon, color: color, size: 48),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha:0.6),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          // URL display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha:0.2)),
            ),
            child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (originalUrl != null) ...[
        Text(
          'Short URL',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          originalUrl!,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const Divider(color: Colors.white12, height: 20),
        Text(
          'Resolved URL',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
      ],
      Text(
        url,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  ),
),
          const SizedBox(height: AppSpacing.lg),
          // Action buttons
          if (!isMalicious && onOpen != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open URL'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (isMalicious)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onBlock ?? onClose,
                icon: const Icon(Icons.block),
                label: const Text('Block & Dismiss'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onClose,
              child: Text(
                'Scan Another',
                style: TextStyle(color: Colors.white.withValues(alpha:0.5)),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}

// Draws corner indicators to guide QR code positioning
class ScannerCornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.deepPurple
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const cornerLength = 30.0;

    canvas.drawLine(Offset.zero, const Offset(cornerLength, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, cornerLength), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - cornerLength, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerLength), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - cornerLength), paint);
    canvas.drawLine(Offset(0, size.height), Offset(cornerLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - cornerLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 

class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha:0.7);
    
    // Scanner area dimensions
    final scannerSize = 280.0;
    final left = (size.width - scannerSize) / 2;
    final top = (size.height - scannerSize) / 2;
  
    // Draw dark overlay everywhere
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(Rect.fromLTWH(left, top, scannerSize, scannerSize))
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Simple shimmer-style animation used during loading states
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  
  const ShimmerLoading({super.key, required this.child});
  
  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.5 + (0.5 * _controller.value),
          child: widget.child,
        );
      },
    );
  }
}