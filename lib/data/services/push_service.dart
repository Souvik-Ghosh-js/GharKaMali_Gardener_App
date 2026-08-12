import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

/// Global navigator key — attached to the MaterialApp in main.dart so that
/// notification taps can navigate without a BuildContext.
final GlobalKey<NavigatorState> gkmNavigatorKey = GlobalKey<NavigatorState>();

/// Background FCM handler. Must be a top-level function. Notification
/// messages are displayed automatically by the OS while the app is in the
/// background — nothing to do here, but the handler must exist.
@pragma('vm:entry-point')
Future<void> gkmFirebaseBackgroundHandler(RemoteMessage message) async {}

class PushService {
  static final PushService instance = PushService._();
  PushService._();

  static const String channelId = 'gkm_gardener';
  static const String channelName = 'Job Alerts';
  static const String _channelDesc = 'New job assignments and booking updates';

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Map<String, dynamic>? _pendingTap;

  /// Registered by the home shell so a notification tap can switch to the
  /// Jobs tab. Call [flushPendingTap] right after registering.
  VoidCallback? onOpenJobs;

  /// Whether Firebase initialized successfully (google-services.json present).
  bool get isReady => _ready;

  /// Initializes Firebase, permissions, channels and message listeners.
  /// Never throws — if Firebase isn't configured (no google-services.json),
  /// the app keeps working and pushes are simply disabled.
  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(gkmFirebaseBackgroundHandler);

      // Notification permission (iOS dialog + Android 13+ POST_NOTIFICATIONS).
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try { await Permission.notification.request(); } catch (_) {}
      }

      // High-importance channel so job alerts heads-up on Android.
      const channel = AndroidNotificationChannel(
        channelId, channelName,
        description: _channelDesc,
        importance: Importance.max,
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (resp) {
          Map<String, dynamic> data = {};
          try {
            final decoded = jsonDecode(resp.payload ?? '{}');
            if (decoded is Map) data = Map<String, dynamic>.from(decoded);
          } catch (_) {}
          _handleTap(data);
        },
      );

      // Foreground messages → show a local notification.
      FirebaseMessaging.onMessage.listen(_showForeground);

      // Taps: app in background → foreground.
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTap(m.data));

      // Tap that launched the app from terminated state.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleTap(initial.data);

      // Keep the backend's copy of the token fresh.
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        try {
          final authed = await ApiService().getToken();
          if (authed != null) await ApiService().updateFcmToken(token);
        } catch (e) {
          if (kDebugMode) print('⚠️ [Push] Token refresh sync failed: $e');
        }
      });

      _ready = true;
      if (kDebugMode) print('✅ [Push] Firebase messaging initialized');
    } catch (e) {
      if (kDebugMode) print('⚠️ [Push] Firebase not configured — notifications disabled: $e');
    }
  }

  /// Current FCM token, or null when Firebase isn't configured.
  Future<String?> getToken() async {
    if (!_ready) return null;
    try { return await FirebaseMessaging.instance.getToken(); } catch (_) { return null; }
  }

  /// On app launch when already logged in: push the token to the backend.
  /// Fire-and-forget — failures are logged, never surfaced.
  Future<void> syncTokenIfLoggedIn() async {
    try {
      final authed = await ApiService().getToken();
      if (authed == null) return;
      final token = await getToken();
      if (token != null) await ApiService().updateFcmToken(token);
    } catch (e) {
      if (kDebugMode) print('⚠️ [Push] Token sync failed: $e');
    }
  }

  /// Replays a tap that arrived before the home shell registered [onOpenJobs].
  void flushPendingTap() {
    final data = _pendingTap;
    if (data == null) return;
    _pendingTap = null;
    _handleTap(data);
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    final title = n?.title ?? message.data['title']?.toString() ?? 'GKM Gardener';
    final body  = n?.body  ?? message.data['body']?.toString()  ?? 'You have a new update.';
    try {
      await _local.show(
        message.hashCode,
        title, body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId, channelName,
            channelDescription: _channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      if (kDebugMode) print('⚠️ [Push] Could not show notification: $e');
    }
  }

  void _handleTap(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final bookingId = int.tryParse(data['booking_id']?.toString() ?? '');

    // Deep link straight to the job when the payload carries a numeric id.
    if (bookingId != null && bookingId > 0) {
      final nav = gkmNavigatorKey.currentState;
      if (nav != null) { nav.pushNamed('/job/$bookingId'); return; }
    }

    // Otherwise anything job-related lands on the Jobs tab.
    final isJobRelated = type == 'new_job' ||
        type == 'booking_assigned' ||
        data.containsKey('booking_number');
    if (!isJobRelated) return;

    if (onOpenJobs != null) {
      gkmNavigatorKey.currentState?.popUntil((r) => r.isFirst);
      onOpenJobs!.call();
    } else {
      // Home shell not mounted yet (cold start) — replay once it registers.
      _pendingTap = data;
    }
  }
}
