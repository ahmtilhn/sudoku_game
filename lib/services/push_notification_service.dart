import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_runtime_config.dart';
import 'firebase_services.dart';
import 'social_api_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseRuntimeConfig.initializeIfConfigured();
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const String _challengeChannelId = 'online_challenges';
  static const String _enabledKey = 'challenge_push_enabled_v1';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  final ValueNotifier<bool> initialized = ValueNotifier<bool>(false);
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> permissionGranted = ValueNotifier<bool>(false);
  final ValueNotifier<String?> openedChallengeId = ValueNotifier<String?>(null);

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  Future<void>? _initialization;

  bool get configured => FirebaseRuntimeConfig.configured;

  Future<void> initialize() {
    if (!configured || initialized.value) return Future<void>.value();
    return _initialization ??= _initializeOnce().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initializeOnce() async {
    try {
      await FirebaseRuntimeConfig.initializeIfConfigured();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      enabled.value = await _preferences.getBool(_enabledKey) ?? false;

      await _initializeLocalNotifications();
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: false,
        sound: true,
      );

      await _tokenSubscription?.cancel();
      await _messageSubscription?.cancel();
      await _openedSubscription?.cancel();

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
      if (enabled.value && permissionGranted.value) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) await _registerToken(token);
      }

      initialized.value = true;
    } catch (error, stackTrace) {
      initialized.value = false;
      debugPrint('Challenge push initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
    }
  }

  Future<bool> requestPermissionAndRegister() async {
    if (!configured) return false;
    if (!initialized.value) await initialize();
    if (!initialized.value) return false;

    try {
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
      if (!allowed) {
        enabled.value = false;
        await _preferences.setBool(_enabledKey, false);
        return false;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return false;

      enabled.value = true;
      await _preferences.setBool(_enabledKey, true);
      await _registerToken(token);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Challenge notification permission failed: $error');
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
      return false;
    }
  }

  Future<void> disableChallengeNotifications() async {
    if (!configured) return;
    if (!initialized.value) await initialize();

    enabled.value = false;
    await _preferences.setBool(_enabledKey, false);

    try {
      await SocialApiClient.instance.disableCurrentDeviceToken();
    } on SocialApiException catch (error, stackTrace) {
      debugPrint('Push token disable failed: $error');
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
    }

    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (error, stackTrace) {
      debugPrint('Local FCM token deletion failed: $error');
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
    }
  }

  Future<void> deleteDeviceToken() => disableChallengeNotifications();

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
    if (!enabled.value) return;
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
    if (!enabled.value || !SocialApiClient.instance.configured || token.isEmpty) {
      return;
    }
    final platform = !kIsWeb && Platform.isIOS ? 'ios' : 'android';
    try {
      await SocialApiClient.instance.registerDeviceToken(
        token: token,
        platform: platform,
      );
    } on SocialApiException catch (error, stackTrace) {
      debugPrint('Push token registration failed: $error');
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
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
