import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Notifications : canal `turns`, permission Android 13+, push FCM (optionnel).
/// Si Firebase n'est pas configuré, l'application fonctionne sans push.
class NotificationService {
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool firebaseReady = false;
  int _nextId = 1;

  /// Appelé quand l'utilisateur ouvre une notification (code du salon).
  void Function(String roomCode)? onOpenRoom;

  /// Vrai si l'app affiche déjà ce salon au premier plan (notification masquée).
  bool Function(String roomCode)? isShowingRoom;

  /// Vrai si ce salon est le salon courant mémorisé ; sinon la notification est ignorée.
  bool Function(String roomCode)? isCurrentRoom;

  /// Appelé avec le jeton FCM (initial et rafraîchi).
  void Function(String token)? onToken;

  static const _channel = AndroidNotificationChannel(
    kNotificationChannelId,
    'Tours de jeu',
    description: 'Prévient quand c\'est ton tour ou qu\'un adversaire a joué.',
    importance: Importance.high,
  );

  Future<void> init() async {
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null && p.isNotEmpty) onOpenRoom?.call(p);
        },
      );
      final android =
          _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);
      await android?.requestNotificationsPermission();
      final launch = await _local.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && payload != null && payload.isNotEmpty) {
        scheduleMicrotask(() => onOpenRoom?.call(payload));
      }
    } catch (e) {
      debugPrint('Notifications locales indisponibles : $e');
    }
    await _initFirebase();
  }

  Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp();
      firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase non configuré, push désactivé : $e');
      return;
    }
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data));
      final initial = await fm.getInitialMessage();
      if (initial != null) scheduleMicrotask(() => _open(initial.data));
      // Jeton FCM classique, celui qu'attend le serveur (HTTP v1 `token`).
      // ignore: deprecated_member_use
      fm.onTokenRefresh.listen((t) => onToken?.call(t));
      // ignore: deprecated_member_use
      final token = await fm.getToken();
      if (token != null) onToken?.call(token);
    } catch (e) {
      debugPrint('FCM indisponible : $e');
    }
  }

  void _open(Map<String, dynamic> data) {
    final code = data['roomCode'];
    if (code is String && code.isNotEmpty) onOpenRoom?.call(code);
  }

  Future<void> _onForeground(RemoteMessage m) async {
    final code = m.data['roomCode'] as String?;
    if (code == null || !(isCurrentRoom?.call(code) ?? false)) return; // salon quitté/abandonné
    if (isShowingRoom?.call(code) ?? false) return;
    final n = m.notification;
    await show(
        title: n?.title ?? m.data['title'] as String? ?? kAppName,
        body: n?.body ?? m.data['body'] as String? ?? '',
        roomCode: code);
  }

  Future<void> show({required String title, required String body, String? roomCode}) async {
    await showLocalNotification(_local, _nextId++, title, body, roomCode);
  }
}

NotificationDetails _details() => const NotificationDetails(
      android: AndroidNotificationDetails(
        kNotificationChannelId,
        'Tours de jeu',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

Future<void> showLocalNotification(FlutterLocalNotificationsPlugin plugin, int id, String title,
    String body, String? roomCode) async {
  try {
    await plugin.show(
      id: id,
      title: title,
      body: body,
      payload: roomCode,
      notificationDetails: _details(),
    );
  } catch (e) {
    debugPrint('Notification impossible : $e');
  }
}

/// Messages data-only reçus en arrière-plan / app fermée : affichés localement (canal `turns`),
/// sauf si le salon n'est plus le salon courant mémorisé.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage m) async {
  final code = m.data['roomCode'] as String?;
  if (code == null || code.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); // l'isolat d'arrière-plan peut avoir un cache périmé
  if (prefs.getString('session.code') != code) return;
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
  );
  final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(NotificationService._channel);
  await showLocalNotification(plugin, DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      m.data['title'] as String? ?? kAppName, m.data['body'] as String? ?? '', code);
}
