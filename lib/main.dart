import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hugeicons/hugeicons.dart';

const _kPrimaryColor = Color(0xFF456FFF);
const _kHomeUrl = 'https://find.vivo.com.cn/h5/home/devices';

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
  bool _hasPromptedSavePassword = false;
  bool _hasShownAutoFillToast = false;

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
            _hasPromptedSavePassword = false;
          },
          onPageFinished: (String url) {
            _saveCookies(url);
            _tryAutoFillPassword();
            _injectPasswordDetector();
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

    // 注册 JS -> Flutter 通信通道
    _webViewController.addJavaScriptChannel(
      'FlutterPasswordBridge',
      onMessageReceived: (JavaScriptMessage message) {
        _onPasswordDetected(message.message);
      },
    );

    _webViewController.loadRequest(Uri.parse(_kHomeUrl));
  }

  // ---- 凭证持久化 ----

  Future<void> _saveCookies(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookies = await _webViewController
          .runJavaScriptReturningResult('document.cookie');
      await prefs.setString('saved_cookies', cookies.toString());
      await prefs.setString('last_url', url);
      await prefs.setInt('last_login', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error saving cookies: $e');
    }
  }

  // ---- 密码检测与保存 ----

  /// 判断元素是否可见
  static const String _jsIsVisible = '''
    function _isVisible(el) {
      if (!el) return false;
      var r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    }
  ''';

  /// 查找可见的密码框和用户名框（优先 placeholder 关键词匹配）
  static const String _jsFindVisibleInputs = '''
    function _findVisibleInputs() {
      var allInputs = document.querySelectorAll('input');
      var pwdInput = null, userInput = null;

      // 第一轮：通过 placeholder 关键词精确匹配
      for (var i = 0; i < allInputs.length; i++) {
        var inp = allInputs[i];
        if (!_isVisible(inp)) continue;
        var p = (inp.placeholder || '');
        if (!pwdInput && (p.indexOf('密码') >= 0 || p.indexOf('password') >= 0)) {
          pwdInput = inp;
        }
        if (!userInput && (p.indexOf('手机号') >= 0 || p.indexOf('账号') >= 0 || p.indexOf('邮箱') >= 0
          || p.indexOf('vivo') >= 0 || p.indexOf('用户') >= 0 || p.indexOf('phone') >= 0)) {
          userInput = inp;
        }
      }

      // 第二轮：通过 type/name 属性匹配（兜底）
      if (!pwdInput || !userInput) {
        for (var i = 0; i < allInputs.length; i++) {
          var inp = allInputs[i];
          if (!_isVisible(inp)) continue;
          var t = (inp.type || '').toLowerCase();
          var n = (inp.name || '').toLowerCase();
          var p = (inp.placeholder || '').toLowerCase();
          if (!pwdInput && t === 'password') {
            pwdInput = inp;
          } else if (!userInput && (t === 'text' || t === 'tel' || t === 'email' || t === 'number'
            || n.indexOf('user') >= 0 || n.indexOf('account') >= 0 || n.indexOf('phone') >= 0 || n.indexOf('mobile') >= 0
            || p.indexOf('号码') >= 0)) {
            userInput = inp;
          }
        }
      }

      return { pwd: pwdInput, user: userInput };
    }
  ''';

  /// 注入 JS 监听密码框输入，表单提交时通知 Flutter
  void _injectPasswordDetector() {
    _webViewController.runJavaScript('''
      (function() {
        if (window._pwdDetectorActive) return;
        window._pwdDetectorActive = true;

        $_jsIsVisible
        $_jsFindVisibleInputs

        function detectAndNotify() {
          var found = _findVisibleInputs();
          if (!found.pwd) return;

          var pwdInput = found.pwd;
          var userInput = found.user;

          function sendCreds() {
            var pwd = pwdInput.value;
            var user = userInput ? userInput.value : '';
            if (pwd && pwd.length >= 4) {
              FlutterPasswordBridge.postMessage(JSON.stringify({
                username: user,
                password: pwd
              }));
            }
          }

          if (!pwdInput._flutterListening) {
            pwdInput._flutterListening = true;
            pwdInput.addEventListener('blur', sendCreds);
            pwdInput.addEventListener('keydown', function(e) {
              if (e.key === 'Enter') sendCreds();
            });
          }

          // 监听所有按钮点击
          var buttons = document.querySelectorAll('button, input[type="submit"], [class*="login"], [class*="submit"], [class*="btn"]');
          buttons.forEach(function(btn) {
            if (!_isVisible(btn)) return;
            if (!btn._flutterListening) {
              btn._flutterListening = true;
              btn.addEventListener('click', function() {
                setTimeout(function() {
                  var f = _findVisibleInputs();
                  if (f.pwd && f.pwd.value) {
                    FlutterPasswordBridge.postMessage(JSON.stringify({
                      username: f.user ? f.user.value : '',
                      password: f.pwd.value
                    }));
                  }
                }, 300);
              });
            }
          });
        }

        detectAndNotify();
        var observer = new MutationObserver(function() { detectAndNotify(); });
        observer.observe(document.body, { childList: true, subtree: true });
      })();
    ''');
  }

  /// 收到密码数据，弹窗询问是否保存
  void _onPasswordDetected(String jsonStr) async {
    if (_hasPromptedSavePassword) return;
    _hasPromptedSavePassword = true;

    try {
      final data = jsonDecode(jsonStr);
      final username = data['username']?.toString() ?? '';
      final password = data['password']?.toString() ?? '';
      if (password.isEmpty) return;

      // 对比已保存的账号密码，完全一致则不弹窗
      final prefs = await SharedPreferences.getInstance();
      final existingUser = prefs.getString('saved_username') ?? '';
      final existingPwd = prefs.getString('saved_password') ?? '';
      final hasSaved = existingUser.isNotEmpty || existingPwd.isNotEmpty;

      if (hasSaved && existingUser == username && existingPwd == password) {
        // 账号密码未变，跳过弹窗
        return;
      }

      final isUpdate = hasSaved;

      if (mounted) _showSavePasswordDialog(username, password, isUpdate: isUpdate);
    } catch (e) {
      debugPrint('Password parse error: $e');
    }
  }

  /// 自动填充已保存的密码
  Future<void> _tryAutoFillPassword() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUsername = prefs.getString('saved_username');
      final savedPassword = prefs.getString('saved_password');
      if (savedUsername == null && savedPassword == null) return;

      // 使用 base64 编码避免 JS 注入中的特殊字符问题
      final usernameB64 = base64Encode(utf8.encode(savedUsername ?? ''));
      final passwordB64 = base64Encode(utf8.encode(savedPassword ?? ''));

      // 注册一个临时通道用于接收填充结果通知
      _webViewController.addJavaScriptChannel(
        'FlutterAutoFillNotify',
        onMessageReceived: (JavaScriptMessage message) {
          if (message.message == 'filled' && mounted && !_hasShownAutoFillToast) {
            _hasShownAutoFillToast = true;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text('正在自动填充密码，请勿操作'),
                  ],
                ),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                margin: const EdgeInsets.all(16),
                backgroundColor: _kPrimaryColor.withOpacity(0.9),
              ),
            );
          }
        },
      );

      await _webViewController.runJavaScript('''
        (function() {
          var _username = atob('$usernameB64');
          var _password = atob('$passwordB64');
          if (!_username && !_password) return;

          $_jsIsVisible
          $_jsFindVisibleInputs

          var filled = false;
          function setNativeValue(el, val) {
            try {
              var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
              nativeSetter.call(el, val);
            } catch(e) {
              el.value = val;
            }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            el.dispatchEvent(new Event('blur', {bubbles: true}));
          }

          function clickPasswordTab() {
            var tabs = document.querySelectorAll('[class*="tab"], [class*="Tab"]');
            for (var i = 0; i < tabs.length; i++) {
              var txt = tabs[i].textContent || '';
              if (txt.indexOf('密码登录') >= 0 && _isVisible(tabs[i])) {
                tabs[i].click();
                return true;
              }
            }
            return false;
          }

          function tryFill() {
            if (filled) return false;
            var found = _findVisibleInputs();
            // 必须同时存在可见的密码框和用户名框才填充
            if (!found.pwd || !found.user) {
              // 尝试点击密码登录 tab
              if (!found.pwd) clickPasswordTab();
              return false;
            }
            if (found.user && _username) {
              setNativeValue(found.user, _username);
            }
            if (found.pwd && _password) {
              setNativeValue(found.pwd, _password);
            }
            filled = true;
            try { FlutterAutoFillNotify.postMessage('filled'); } catch(e) {}
            return true;
          }

          if (!tryFill()) {
            var observer = new MutationObserver(function() {
              if (tryFill()) observer.disconnect();
            });
            if (document.body) {
              observer.observe(document.body, { childList: true, subtree: true });
            }
            var attempts = 0;
            var timer = setInterval(function() {
              attempts++;
              if (tryFill() || attempts >= 20) {
                clearInterval(timer);
                if (observer) observer.disconnect();
              }
            }, 500);
          }
        })();
      ''');
    } catch (e) {
      debugPrint('Auto fill error: $e');
    }
  }

  /// 保存密码到本地
  Future<void> _savePassword(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_username', username);
    await prefs.setString('saved_password', password);
  }

  /// 删除已保存的密码
  Future<void> _deleteSavedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');
  }

  // ---- 清除凭证 ----

  Future<void> _clearCookies({bool alsoDeletePassword = false}) async {
    try {
      final cookieManager = WebViewCookieManager();
      await cookieManager.clearCookies();

      await _webViewController.runJavaScript(
          'document.cookie.split(";").forEach(function(c) { document.cookie = c.trim().split("=")[0] + "=;expires=Thu, 01 Jan 1970 00:00:00 UTC;path=/"; });');

      await _webViewController
          .runJavaScript('localStorage.clear(); sessionStorage.clear();');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_cookies');
      await prefs.remove('last_url');
      await prefs.remove('last_login');

      if (alsoDeletePassword) {
        await _deleteSavedPassword();
      }

      if (mounted) {
        _hasShownAutoFillToast = false; // 重置，下次登录可再次提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(alsoDeletePassword ? '已清除凭证和保存的密码' : '已清除登录凭证'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
            backgroundColor: _kPrimaryColor.withOpacity(0.9),
          ),
        );
      }

      await _webViewController.loadRequest(Uri.parse(_kHomeUrl));
    } catch (e) {
      debugPrint('Error clearing cookies: $e');
    }
  }

  // ---- 导航 ----

  Future<void> _goHome() async {
    setState(() => _isLoading = true);
    await _webViewController.loadRequest(Uri.parse(_kHomeUrl));
  }

  Future<void> _reloadPage() async {
    setState(() => _isLoading = true);
    // 先清空表单，再通过加时间戳强制重新加载（避免缓存）
    await _webViewController.runJavaScript(
      'document.querySelectorAll("input").forEach(function(i){i.value=""});'
    );
    final currentUrl = await _webViewController.currentUrl();
    final uri = Uri.parse(currentUrl ?? _kHomeUrl);
    // 加时间戳强制绕过缓存
    final freshUri = uri.replace(queryParameters: {
      ...uri.queryParameters,
      '_t': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    await _webViewController.loadRequest(freshUri);
  }

  // ---- 图标背景组件 ----

  Widget _buildIconBadge(dynamic icon,
      {double size = 22, double boxSize = 48}) {
    return Container(
      width: boxSize,
      height: boxSize,
      decoration: BoxDecoration(
        color: _kPrimaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: HugeIcon(icon: icon, size: size, color: _kPrimaryColor),
      ),
    );
  }

  // ---- UI ----

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
                    _buildIconBadge(
                      HugeIcons.strokeRoundedInformationSquare,
                      size: 22,
                      boxSize: 48,
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

  // ---- 保存密码弹窗 ----

  void _showSavePasswordDialog(String username, String password, {bool isUpdate = false}) {
    if (!mounted) return;
    bool showPassword = false;
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final maskedPwd = '*' * password.length;
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
                    _buildIconBadge(HugeIcons.strokeRoundedLocked),
                    const SizedBox(height: 16),
                    Text(
                      isUpdate ? '更新密码' : '保存密码',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (username.isNotEmpty)
                            Text(
                              '账号: $username',
                              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            ),
                          if (username.isNotEmpty) const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(opacity: animation, child: child);
                                  },
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      showPassword ? '密码: $password' : '密码: $maskedPwd',
                                      key: ValueKey<bool>(showPassword),
                                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    showPassword = !showPassword;
                                  });
                                },
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(opacity: animation, child: child);
                                  },
                                  child: Icon(
                                    showPassword ? Icons.visibility : Icons.visibility_off,
                                    key: ValueKey<bool>(showPassword),
                                    size: 18,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
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
                            child: Text(isUpdate ? '取消' : '不保存'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _savePassword(username, password);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isUpdate ? '密码已更新' : '密码已保存'),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  margin: const EdgeInsets.all(16),
                                  backgroundColor: _kPrimaryColor.withOpacity(0.9),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPrimaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(isUpdate ? '更新' : '保存'),
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
      },
    );
  }

  // ---- 清除凭证弹窗（带密码勾选） ----

  void _showClearDialog() {
    bool deletePassword = false;
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                    _buildIconBadge(HugeIcons.strokeRoundedDelete02),
                    const SizedBox(height: 16),
                    const Text(
                      '清除登录凭证',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '清除后需要重新登录',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    // 勾选框
                    GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          deletePassword = !deletePassword;
                        });
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: deletePassword,
                              onChanged: (v) {
                                setDialogState(() {
                                  deletePassword = v ?? false;
                                });
                              },
                              activeColor: _kPrimaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              side: BorderSide(
                                  color: Colors.grey[400]!, width: 1.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '同时删除保存的密码',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
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
                              _clearCookies(alsoDeletePassword: deletePassword);
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
      },
    );
  }
}
