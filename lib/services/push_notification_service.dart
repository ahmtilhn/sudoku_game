import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_runtime_config.dart';
import 'social_api_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!FirebaseRuntimeConfig.configured) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: FirebaseRuntimeConfig.options);
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const String _challengeChannelId = 'online_challenges';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<bool> initialized = ValueNotifier<bool>(false);
  final ValueNotifier<bool> permissionGranted = ValueNotifier<bool>(false);
  final ValueNotifier<String?> openedChallengeId = ValueNotifier<String?>(null);

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;

  bool get configured => FirebaseRuntimeConfig.configured;

  Future<void> initialize() async {
    if (!configured || initialized.value) return;

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: FirebaseRuntimeConfig.options);
    }
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }

    await _initializeLocalNotifications();
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: false,
      sound: true,
    );

    _messageSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedMessage,
    );
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      _registerToken,
    );

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _handleOpenedMessage(initialMessage);

    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    permissionGranted.value = _isAuthorized(settings.authorizationStatus);
    if (permissionGranted.value) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    }

    initialized.value = true;
  }

  Future<bool> requestPermissionAndRegister() async {
    if (!configured) return false;
    if (!initialized.value) await initialize();

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    final allowed = _isAuthorized(settings.authorizationStatus);
    permissionGranted.value = allowed;
    if (!allowed) return false;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return false;
    await _registerToken(token);
    return true;
  }

  Future<void> deleteDeviceToken() async {
    if (!configured) return;
    await FirebaseMessaging.instance.deleteToken();
    permissionGranted.value = false;
  }

  Future<void> _initializeLocalNotifications() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final challengeId = response.payload;
        if (challengeId != null && challengeId.isNotEmpty) {
          openedChallengeId.value = challengeId;
        }
      },
    );

    if (!kIsWeb && Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _challengeChannelId,
              'Online challenges',
              description:
                  'Invitations and updates for online Sudoku challenges.',
              importance: Importance.high,
            ),
          );
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final challengeId = message.data['challengeId']?.toString();
    if (challengeId == null || challengeId.isEmpty) return;

    if (!kIsWeb && Platform.isAndroid) {
      await _localNotifications.show(
        id: challengeId.hashCode & 0x7fffffff,
        title: message.notification?.title ?? 'New Sudoku challenge',
        body: message.notification?.body ??
            'A player challenged you. Open Sudoku Duel to respond.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _challengeChannelId,
            'Online challenges',
            channelDescription:
                'Invitations and updates for online Sudoku challenges.',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: challengeId,
      );
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final challengeId = message.data['challengeId']?.toString();
    if (challengeId != null && challengeId.isNotEmpty) {
      openedChallengeId.value = challengeId;
    }
  }

  Future<void> _registerToken(String token) async {
    if (!SocialApiClient.instance.configured || token.isEmpty) return;
    final platform = !kIsWeb && Platform.isIOS ? 'ios' : 'android';
    try {
      await SocialApiClient.instance.registerDeviceToken(
        token: token,
        platform: platform,
      );
    } on SocialApiException catch (error) {
      debugPrint('Push token registration failed: $error');
    }
  }

  bool _isAuthorized(AuthorizationStatus status) {
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _openedSubscription?.cancel();
  }
}
