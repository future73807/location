import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hugeicons/hugeicons.dart';

const _kPrimaryColor = Color(0xFF456FFF);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'vivo设备查找',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _kPrimaryColor,
          primary: _kPrimaryColor,
        ),
        useMaterial3: true,
      ),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _webViewController;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _errorMessage = '';
            });
          },
          onPageFinished: (String url) {
            _saveCookies(url);
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
              _errorMessage = '加载失败: ${error.description}';
            });
          },
        ),
      );

    // 启用 DOM Storage 和数据库存储，确保登录状态持久化
    final platform = _webViewController.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      platform.setMediaPlaybackRequiresUserGesture(false);
    }

    _webViewController
        .loadRequest(Uri.parse('https://find.vivo.com.cn/h5/home/devices'));
  }

  Future<void> _saveCookies(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 通过JavaScript获取cookies
      final cookies = await _webViewController
          .runJavaScriptReturningResult('document.cookie');

      await prefs.setString('saved_cookies', cookies.toString());
      await prefs.setString('last_url', url);
      await prefs.setInt('last_login', DateTime.now().millisecondsSinceEpoch);

      debugPrint('Cookies saved successfully');
    } catch (e) {
      debugPrint('Error saving cookies: $e');
    }
  }

  Future<void> _clearCookies() async {
    try {
      // 清除 WebView CookieManager（真正的cookie存储）
      final cookieManager = WebViewCookieManager();
      await cookieManager.clearCookies();

      // 清除 JS 层的 cookie
      await _webViewController.runJavaScript(
          'document.cookie.split(";").forEach(function(c) { document.cookie = c.trim().split("=")[0] + "=;expires=Thu, 01 Jan 1970 00:00:00 UTC;path=/"; });');

      // 清除本地存储和 sessionStorage
      await _webViewController
          .runJavaScript('localStorage.clear(); sessionStorage.clear();');

      // 清除 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_cookies');
      await prefs.remove('last_url');
      await prefs.remove('last_login');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已清除登录凭证'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }

      // 重新加载登录页
      await _webViewController
          .loadRequest(Uri.parse('https://find.vivo.com.cn/h5/home/devices'));
    } catch (e) {
      debugPrint('Error clearing cookies: $e');
    }
  }

  Future<void> _goHome() async {
    setState(() {
      _isLoading = true;
    });
    await _webViewController
        .loadRequest(Uri.parse('https://find.vivo.com.cn/h5/home/devices'));
  }

  Future<void> _reloadPage() async {
    setState(() {
      _isLoading = true;
    });
    final currentUrl = await _webViewController.currentUrl();
    await _webViewController.loadRequest(
        Uri.parse(currentUrl ?? 'https://find.vivo.com.cn/h5/home/devices'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        backgroundColor: _kPrimaryColor,
        foregroundColor: Colors.white,
        title: const Text('vivo设备查找', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedHome01,
                color: Colors.white,
                size: 20),
            onPressed: _goHome,
            tooltip: '主页',
          ),
          IconButton(
            icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedSquareArrowReload02,
                color: Colors.white,
                size: 20),
            onPressed: _reloadPage,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedDelete02,
                color: Colors.white,
                size: 20),
            onPressed: _showClearDialog,
            tooltip: '清除凭证',
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webViewController),
          if (_isLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                color: _kPrimaryColor,
                backgroundColor: _kPrimaryColor.withOpacity(0.12),
                minHeight: 2.5,
              ),
            ),
          if (_errorMessage.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _kPrimaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const HugeIcon(
                        icon: HugeIcons.strokeRoundedInformationSquare,
                        size: 30,
                        color: _kPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '加载失败',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: 140,
                      child: OutlinedButton(
                        onPressed: _reloadPage,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kPrimaryColor,
                          side: BorderSide(
                              color: _kPrimaryColor.withOpacity(0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('重新加载'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _kPrimaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const HugeIcon(
                      icon: HugeIcons.strokeRoundedDelete02,
                      size: 22,
                      color: _kPrimaryColor),
                ),
                const SizedBox(height: 16),
                const Text(
                  '清除登录凭证',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '清除后需要重新登录',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kPrimaryColor,
                          side: BorderSide(
                              color: _kPrimaryColor.withOpacity(0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _clearCookies();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('确认清除'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
