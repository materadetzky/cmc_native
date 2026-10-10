import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void Function(String url)? _globalNotificationNavigate;

Future<void> _initNotifications() async {
  try {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _globalNotificationNavigate?.call(payload);
        }
      },
    );

    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'cmc_center_notifications',
        'CMC.CENTER Értesítések',
        description: 'Valós idejű push értesítések és rendszerriasztások',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await androidImplementation.createNotificationChannel(channel);
    }
  } catch (e) {
    debugPrint('[CMC NOTIFICATIONS] Init error: $e');
  }
}

Future<void> _showLocalNotification({
  required int id,
  required String title,
  required String body,
  String? payload,
}) async {
  try {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'cmc_center_notifications',
      'CMC.CENTER Értesítések',
      channelDescription: 'Valós idejű push értesítések és rendszerriasztások',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
      enableVibration: true,
      color: Color(0xFF00F0FF),
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails darwinPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: darwinPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: payload,
    );
  } catch (e) {
    debugPrint('[CMC NOTIFICATIONS] Show error: $e');
  }
}

/// Native Dart Background Notification Poller
class CmcNotificationPoller {
  static const String apiUrl = 'https://center.cisztermedia-szfvar.hu';
  static const String apiAuthKey = 'cmc-super-secret-key-2026';

  Timer? _timer;
  final Set<String> _seenAlertIds = <String>{};
  final Set<String> _seenMessageIds = <String>{};
  bool _initialized = false;
  String? currentUsername;
  String? currentUserId;
  String? currentUserRole;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => poll());
    poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void syncUser({String? username, String? id, String? role}) {
    currentUsername = username;
    currentUserId = id;
    currentUserRole = role;
  }

  Future<void> poll() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);

      // 1. Poll CMC alerts & broadcasts
      final alertsReq =
          await client.getUrl(Uri.parse('$apiUrl/api/db/cmc_alerts'));
      alertsReq.headers.set('x-cmc-auth', apiAuthKey);
      final alertsRes = await alertsReq.close();
      if (alertsRes.statusCode == 200) {
        final alertsBody = await alertsRes.transform(utf8.decoder).join();
        final dynamic decoded = jsonDecode(alertsBody);
        if (decoded is List) {
          _processAlerts(decoded);
        }
      }

      // 2. Poll private messages if user is known
      if (currentUsername != null || currentUserId != null) {
        final msgsReq =
            await client.getUrl(Uri.parse('$apiUrl/api/db/cmc_messages'));
        msgsReq.headers.set('x-cmc-auth', apiAuthKey);
        final msgsRes = await msgsReq.close();
        if (msgsRes.statusCode == 200) {
          final msgsBody = await msgsRes.transform(utf8.decoder).join();
          final dynamic decoded = jsonDecode(msgsBody);
          if (decoded is List) {
            _processMessages(decoded);
          }
        }
      }
    } catch (_) {
      // Ignore network timeouts silently
    }
  }

  void _processAlerts(List<dynamic> alerts) {
    if (!_initialized) {
      // Seed IDs on startup so we don't spam old alerts
      for (final a in alerts) {
        if (a is Map && a['id'] != null) {
          _seenAlertIds.add(a['id'].toString());
        }
      }
      _initialized = true;
      return;
    }

    for (final a in alerts) {
      if (a is! Map) continue;
      final String idStr = a['id']?.toString() ?? '';
      if (idStr.isEmpty || _seenAlertIds.contains(idStr)) continue;

      _seenAlertIds.add(idStr);

      final String rawMessage = a['message']?.toString() ?? '';
      if (rawMessage.isEmpty || rawMessage.startsWith('auditAlert|')) {
        continue;
      }

      // Check recipient targeting
      bool isTargeted = false;
      final dynamic targetUsers = a['targetUsers'];
      final dynamic targetRoles = a['targetRoles'];
      final dynamic target = a['target'];
      final bool targetAll = a['targetAll'] == true;

      if (targetAll || target == 'all' || target == null) {
        isTargeted = true;
      } else if (currentUsername != null &&
          targetUsers is List &&
          targetUsers.contains(currentUsername)) {
        isTargeted = true;
      } else if (target == 'admin' && currentUserRole == 'admin') {
        isTargeted = true;
      } else if (currentUserRole != null &&
          targetRoles is List &&
          targetRoles.contains(currentUserRole)) {
        isTargeted = true;
      } else if (target == currentUsername) {
        isTargeted = true;
      } else {
        isTargeted = target == null || target == 'all';
      }

      if (isTargeted) {
        final cleanBody = _stripHtml(rawMessage);
        final sender = a['sender']?.toString() ?? '';
        final title = a['title']?.toString() ??
            (sender.isNotEmpty
                ? 'CMC Broadcast (@$sender)'
                : 'CMC.CENTER Broadcast');

        _showLocalNotification(
          id: idStr.hashCode.abs(),
          title: title,
          body: cleanBody.isNotEmpty ? cleanBody : 'Új rendszerértesítés érkezett.',
          payload: '/dashboard',
        );
      }
    }
  }

  void _processMessages(List<dynamic> messages) {
    for (final m in messages) {
      if (m is! Map) continue;
      final String idStr = m['id']?.toString() ?? '';
      if (idStr.isEmpty || _seenMessageIds.contains(idStr)) continue;

      _seenMessageIds.add(idStr);

      final dynamic to = m['to'];
      final String from = m['from']?.toString() ?? '';
      if (from == currentUserId || from == currentUsername) continue;

      bool isForMe = false;
      if (to == currentUserId || to == currentUsername || to == 'all') {
        isForMe = true;
      } else if (to is List &&
          (to.contains(currentUserId) || to.contains(currentUsername))) {
        isForMe = true;
      }

      if (isForMe) {
        final subject = m['subject']?.toString() ?? 'Új üzenet';
        final body = _stripHtml(m['body']?.toString() ?? '');
        _showLocalNotification(
          id: idStr.hashCode.abs(),
          title: 'Új üzenet: $subject',
          body: body.length > 100 ? '${body.substring(0, 97)}...' : body,
          payload: '/email-interface',
        );
      }
    }
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF0D1117),
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  runApp(const CmcNativeApp());
}

class CmcNativeApp extends StatelessWidget {
  const CmcNativeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CMC.CENTER',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F0FF),
          secondary: Color(0xFF2563EB),
          surface: Color(0xFF161B22),
        ),
      ),
      home: const CmcWebViewScreen(),
    );
  }
}

class CmcWebViewScreen extends StatefulWidget {
  const CmcWebViewScreen({super.key});

  static const String initialUrl = 'https://center.cisztermedia-szfvar.hu';

  @override
  State<CmcWebViewScreen> createState() => _CmcWebViewScreenState();
}

class _CmcWebViewScreenState extends State<CmcWebViewScreen> {
  late final WebViewController _controller;
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<double> _loadingProgress = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _hasError = ValueNotifier<bool>(false);
  String _errorMessage = '';
  DateTime? _lastBackPressTime;
  final CmcNotificationPoller _poller = CmcNotificationPoller();

  static const String _nativeBridgeJsScript = r'''
(function() {
  try {
    if (window._cmcNativeBridgeActive) return;
    window._cmcNativeBridgeActive = true;

    // 1. Safe window.Notification Polyfill
    function CmcNativeNotification(title, options) {
      options = options || {};
      this.title = title || 'CMC.CENTER';
      this.body = options.body || '';
      this.icon = options.icon || '';
      this.tag = options.tag || '';
      this.data = options.data || {};

      try {
        if (window.CmcNativeBridge) {
          window.CmcNativeBridge.postMessage(JSON.stringify({
            type: 'SHOW_NOTIFICATION',
            title: this.title,
            body: this.body,
            icon: this.icon,
            tag: this.tag,
            data: this.data
          }));
        }
      } catch(e) {}
    }

    CmcNativeNotification.permission = 'granted';
    CmcNativeNotification.maxActions = 2;
    CmcNativeNotification.requestPermission = function(cb) {
      try {
        if (window.CmcNativeBridge) {
          window.CmcNativeBridge.postMessage(JSON.stringify({
            type: 'REQUEST_NOTIFICATION_PERMISSION'
          }));
        }
      } catch(e) {}
      if (typeof cb === 'function') cb('granted');
      return Promise.resolve('granted');
    };

    window.Notification = CmcNativeNotification;

    // 2. Safe PushManager Mock for ServiceWorker registrations
    var deviceId = localStorage.getItem('cmc_native_device_id');
    if (!deviceId) {
      deviceId = 'native_' + Date.now().toString(36) + '_' + Math.random().toString(36).substring(2, 8);
      localStorage.setItem('cmc_native_device_id', deviceId);
    }

    var nativePushSub = {
      endpoint: 'https://center.cisztermedia-szfvar.hu/api/pwa/native/' + deviceId,
      expirationTime: null,
      options: { userVisibleOnly: true, applicationServerKey: null },
      toJSON: function() {
        return {
          endpoint: this.endpoint,
          expirationTime: null,
          keys: {
            p256dh: 'BCmCNativePushPolyfillP256dhKeyForNativeAppNotifications2026',
            auth: 'NativeAuthSecret2026'
          }
        };
      },
      getKey: function(k) { return new Uint8Array([1, 2, 3, 4]); },
      unsubscribe: function() {
        localStorage.setItem('push_notifications_enabled', 'false');
        try {
          if (window.CmcNativeBridge) {
            window.CmcNativeBridge.postMessage(JSON.stringify({ type: 'PUSH_UNSUBSCRIBE' }));
          }
        } catch(e) {}
        return Promise.resolve(true);
      }
    };

    var nativePushManager = {
      getSubscription: function() {
        var enabled = localStorage.getItem('push_notifications_enabled') === 'true';
        return Promise.resolve(enabled ? nativePushSub : null);
      },
      subscribe: function(opts) {
        localStorage.setItem('push_notifications_enabled', 'true');
        try {
          if (window.CmcNativeBridge) {
            window.CmcNativeBridge.postMessage(JSON.stringify({
              type: 'PUSH_SUBSCRIBE',
              endpoint: nativePushSub.endpoint
            }));
          }
        } catch(e) {}
        return Promise.resolve(nativePushSub);
      },
      permissionState: function() { return Promise.resolve('granted'); }
    };

    if (typeof ServiceWorkerRegistration !== 'undefined') {
      try {
        Object.defineProperty(ServiceWorkerRegistration.prototype, 'pushManager', {
          get: function() { return nativePushManager; },
          configurable: true
        });
      } catch(e) {}
    }

    if (typeof navigator !== 'undefined' && navigator.serviceWorker && navigator.serviceWorker.ready) {
      navigator.serviceWorker.ready.then(function(reg) {
        if (reg && !reg.pushManager) {
          try { reg.pushManager = nativePushManager; } catch(e) {}
        }
      }).catch(function() {});
    }

    // 3. User Sync to Dart
    function syncLoggedInUser() {
      try {
        var savedUser = localStorage.getItem('cmc_logged_in_user');
        if (savedUser && window.CmcNativeBridge) {
          window.CmcNativeBridge.postMessage(JSON.stringify({
            type: 'USER_SYNC',
            username: savedUser
          }));
        }
      } catch(e) {}
    }
    syncLoggedInUser();
    setInterval(syncLoggedInUser, 10000);

    // 4. Intercept API Alert & Broadcast fetches directly in the browser
    var origFetch = window.fetch;
    if (origFetch) {
      window.fetch = async function() {
        var res = await origFetch.apply(this, arguments);
        try {
          var url = typeof arguments[0] === 'string' ? arguments[0] : (arguments[0] && arguments[0].url) || '';
          if (url.indexOf('/api/db/cmc_alerts') !== -1 || url.indexOf('/api/alerts') !== -1) {
            res.clone().json().then(function(alerts) {
              if (Array.isArray(alerts) && alerts.length > 0) {
                if (window._cmcLastAlertId === undefined) {
                  window._cmcLastAlertId = alerts[0].id;
                  return;
                }
                for (var i = 0; i < alerts.length; i++) {
                  var a = alerts[i];
                  if (a && a.id > window._cmcLastAlertId) {
                    window._cmcLastAlertId = a.id;
                    if (a.message && a.message.indexOf('auditAlert|') === -1) {
                      var clean = a.message.replace(/<[^>]*>/g, '').trim();
                      if (window.CmcNativeBridge) {
                        window.CmcNativeBridge.postMessage(JSON.stringify({
                          type: 'SHOW_NOTIFICATION',
                          title: a.title || (a.sender ? 'CMC Broadcast (@' + a.sender + ')' : 'CMC.CENTER Broadcast'),
                          body: clean,
                          data: { url: '/dashboard' }
                        }));
                      }
                    }
                  }
                }
              }
            }).catch(function() {});
          }
        } catch(e) {}
        return res;
      };
    }

    // 5. Global helper for manual test trigger
    window.sendCmcNativePush = function(title, body, url) {
      new window.Notification(title || 'CMC.CENTER', {
        body: body || 'Teszt értesítés a natív appból',
        data: { url: url || '/' }
      });
    };

    console.log('[CMC NATIVE] ✅ Full Web Push & Broadcast Bridge active.');
  } catch(err) {
    console.warn('[CMC NATIVE BRIDGE] Initialization note:', err);
  }
})();
''';

  @override
  void initState() {
    super.initState();
    _globalNotificationNavigate = _handleNotificationNavigation;
    _initNotifications();
    _requestAppPermissions();
    _initializeWebViewController();
    _poller.start();
  }

  @override
  void dispose() {
    _poller.stop();
    _isLoading.dispose();
    _loadingProgress.dispose();
    _hasError.dispose();
    _globalNotificationNavigate = null;
    super.dispose();
  }

  void _handleNotificationNavigation(String urlPath) {
    if (!mounted) return;
    if (urlPath.isNotEmpty) {
      final target = urlPath.startsWith('http')
          ? urlPath
          : '${CmcWebViewScreen.initialUrl}${urlPath.startsWith('/') ? '' : '/'}$urlPath';
      _controller.loadRequest(Uri.parse(target));
    }
  }

  Future<void> _requestAppPermissions() async {
    try {
      await [
        Permission.camera,
        Permission.microphone,
        Permission.notification,
      ].request();
    } catch (e) {
      debugPrint('Permission request error: $e');
    }
  }

  Future<void> _handleBridgeMessage(String rawJson) async {
    try {
      final Map<String, dynamic> data = jsonDecode(rawJson);
      final String type = data['type'] ?? '';

      if (type == 'REQUEST_NOTIFICATION_PERMISSION') {
        final status = await Permission.notification.request();
        final granted = status.isGranted;
        _controller.runJavaScript(
          "if (window.Notification) window.Notification.permission = '${granted ? 'granted' : 'denied'}';",
        );
      } else if (type == 'SHOW_NOTIFICATION') {
        final String title = data['title'] ?? 'CMC.CENTER';
        final String body = data['body'] ?? '';
        final String? url = data['data'] is Map ? data['data']['url'] : null;

        await _showLocalNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: title,
          body: body,
          payload: url,
        );
      } else if (type == 'USER_SYNC') {
        final String username = data['username'] ?? '';
        final String id = data['id'] ?? '';
        final String role = data['role'] ?? '';
        _poller.syncUser(username: username, id: id, role: role);
      } else if (type == 'PUSH_SUBSCRIBE') {
        debugPrint('[CMC NATIVE] Push subscribed: ${data['endpoint']}');
        await _showLocalNotification(
          id: 9991,
          title: 'CMC.CENTER',
          body: 'Push értesítések sikeresen bekapcsolva a natív appban!',
          payload: '/profile',
        );
      } else if (type == 'PUSH_UNSUBSCRIBE') {
        debugPrint('[CMC NATIVE] Push unsubscribed.');
      }
    } catch (e) {
      debugPrint('[CMC NATIVE BRIDGE] Message parse error: $e');
    }
  }

  void _injectBridgeScript() {
    _controller.runJavaScript(_nativeBridgeJsScript).catchError((e) {
      debugPrint('[CMC NATIVE] Script injection note: $e');
    });
  }

  void _initializeWebViewController() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(params);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0D1117))
      ..setUserAgent('Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36 CMC-Native-App/2.10.2')
      ..addJavaScriptChannel(
        'CmcNativeBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleBridgeMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            _loadingProgress.value = progress / 100.0;
          },
          onPageStarted: (String url) {
            _isLoading.value = true;
            _hasError.value = false;
            _errorMessage = '';
          },
          onPageFinished: (String url) {
            _isLoading.value = false;
            _injectBridgeScript();
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame ?? true) {
              _hasError.value = true;
              _isLoading.value = false;
              _errorMessage = error.description;
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            if (uri.scheme == 'tel' ||
                uri.scheme == 'mailto' ||
                uri.scheme == 'sms' ||
                uri.scheme == 'whatsapp' ||
                uri.scheme == 'intent') {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            }

            if (uri.host.contains('cisztermedia-szfvar.hu') ||
                uri.host.contains('script.google.com') ||
                uri.host.contains('accounts.google.com') ||
                uri.host.contains('docs.google.com')) {
              return NavigationDecision.navigate;
            }

            if (request.isMainFrame && !uri.host.contains('cisztermedia')) {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                return NavigationDecision.prevent;
              }
            }

            return NavigationDecision.navigate;
          },
        ),
      );

    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setOverScrollMode(WebViewOverScrollMode.never);
      androidController.setOnPlatformPermissionRequest((request) {
        request.grant();
      });
      androidController.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async =>
            const GeolocationPermissionsResponse(allow: true, retain: true),
      );
    }

    controller.loadRequest(Uri.parse(CmcWebViewScreen.initialUrl));
    _controller = controller;
  }

  Future<void> _handleBackPress() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return;
    }

    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Nyomd meg újra a kilépéshez!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: const Color(0xFF161B22),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0x3300F0FF)),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackPress();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        body: SafeArea(
          top: true,
          bottom: false,
          child: Stack(
            children: [
              // 1. High-Performance Native WebView (Zero RefreshIndicator overhead)
              WebViewWidget(controller: _controller),

              // 2. High-Tech Cyan Progress Bar (Isolated listener - zero WebView rebuilds)
              ValueListenableBuilder<bool>(
                valueListenable: _isLoading,
                builder: (context, isLoading, _) {
                  if (!isLoading) return const SizedBox.shrink();
                  return ValueListenableBuilder<double>(
                    valueListenable: _loadingProgress,
                    builder: (context, progress, _) {
                      return Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: progress < 1.0 ? progress : null,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF00F0FF),
                          ),
                          minHeight: 2.5,
                        ),
                      );
                    },
                  );
                },
              ),

              // 3. Fullscreen splash / loading overlay (Disappears cleanly on page finish)
              ValueListenableBuilder<bool>(
                valueListenable: _isLoading,
                builder: (context, isLoading, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _hasError,
                    builder: (context, hasError, _) {
                      if (!isLoading || hasError) return const SizedBox.shrink();
                      return Positioned.fill(
                        child: Container(
                          color: const Color(0xFF0D1117),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CmcLogoWidget(size: 96),
                                const SizedBox(height: 24),
                                const Text(
                                  'CMC.CENTER',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Kapcsolódás a védett hálózathoz...',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF00F0FF),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              // 4. High-tech offline / connection error screen
              ValueListenableBuilder<bool>(
                valueListenable: _hasError,
                builder: (context, hasError, _) {
                  if (!hasError) return const SizedBox.shrink();
                  return Positioned.fill(
                    child: Container(
                      color: const Color(0xFF0D1117),
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                ),
                                child: const Icon(
                                  Icons.wifi_off_rounded,
                                  size: 40,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Kapcsolati Hiba',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage.isNotEmpty
                                    ? _errorMessage
                                    : 'A CMC.CENTER szerver jelenleg nem érhető el vagy nincs internetkapcsolat.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    _hasError.value = false;
                                    _isLoading.value = true;
                                    _controller.reload();
                                  },
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  label: const Text(
                                    'ÚJRAPRÓBÁLKOZÁS',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Official Circular CMC.CENTER Logo Widget
class CmcLogoWidget extends StatelessWidget {
  final double size;

  const CmcLogoWidget({super.key, this.size = 88});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0A0A0A),
        border: Border.all(
          color: const Color(0xFF1E3A8A).withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00F0FF).withValues(alpha: 0.35),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/icon.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Stack(
            alignment: Alignment.center,
            children: [
              Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF1E40AF).withValues(alpha: 0.4),
                    width: 1.0,
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(-1.5, 0),
                child: Text(
                  'CMC',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontWeight: FontWeight.w900,
                    fontSize: size * 0.38,
                    color: const Color(0xFF00F0FF),
                    letterSpacing: -1.5,
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(1.5, 0),
                child: Text(
                  'CMC',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontWeight: FontWeight.w900,
                    fontSize: size * 0.38,
                    color: const Color(0xFFFFB000),
                    letterSpacing: -1.5,
                  ),
                ),
              ),
              Text(
                'CMC',
                style: TextStyle(
                  fontFamily: 'Arial',
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.38,
                  color: Colors.white,
                  letterSpacing: -1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
