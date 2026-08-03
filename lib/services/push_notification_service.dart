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
  final ValueNotifier<String?> openedChallengeId =
      _ConsumableValueNotifier<String>();
  final ValueNotifier<String?> openedRematchId =
      _ConsumableValueNotifier<String>();

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

      final signedIn = await _ensureAnonymousSession();
      if (!signedIn) return;

      enabled.value = await _preferences.getBool(_enabledKey) ?? false;

      await _initializeLocalNotifications();
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
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

      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) _handleOpenedMessage(initialMessage);

      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
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

  Future<bool> _ensureAnonymousSession() async {
    if (FirebaseAuth.instance.currentUser != null) return true;
    try {
      await FirebaseAuth.instance.signInAnonymously();
      return FirebaseAuth.instance.currentUser != null;
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint('Anonymous Firebase sign-in failed: ${error.code}');
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
      return false;
    } catch (error, stackTrace) {
      debugPrint('Anonymous Firebase sign-in failed: $error');
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
      return false;
    }
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
        _handleLocalPayload(response.payload);
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
                  'Invitations and updates for online Sudoku challenges and rematches.',
              importance: Importance.high,
            ),
          );
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (!enabled.value) return;
    final target = _notificationTarget(message.data);
    if (target == null) return;

    if (!kIsWeb && Platform.isAndroid) {
      await _localNotifications.show(
        id: target.id.hashCode & 0x7fffffff,
        title: message.notification?.title ?? target.defaultTitle,
        body: message.notification?.body ?? target.defaultBody,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _challengeChannelId,
            'Online challenges',
            channelDescription:
                'Invitations and updates for online Sudoku challenges and rematches.',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: '${target.type}:${target.id}',
      );
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final target = _notificationTarget(message.data);
    if (target == null) return;
    _openTarget(target);
  }

  void _handleLocalPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final separator = payload.indexOf(':');
    if (separator <= 0) {
      openedChallengeId.value = payload;
      return;
    }
    final type = payload.substring(0, separator);
    final id = payload.substring(separator + 1);
    if (id.isEmpty) return;
    _openTarget(_PushTarget(type: type, id: id));
  }

  _PushTarget? _notificationTarget(Map<String, dynamic> data) {
    final rematchId = data['rematchId']?.toString();
    if (rematchId != null && rematchId.isNotEmpty) {
      return _PushTarget(
        type: 'rematch',
        id: rematchId,
        defaultTitle: 'Rematch invitation',
        defaultBody:
            'A player wants to play again. Open Sudoku Duel to respond.',
      );
    }
    final challengeId = data['challengeId']?.toString();
    if (challengeId != null && challengeId.isNotEmpty) {
      return _PushTarget(
        type: 'challenge',
        id: challengeId,
        defaultTitle: 'New Sudoku challenge',
        defaultBody: 'A player challenged you. Open Sudoku Duel to respond.',
      );
    }
    return null;
  }

  void _openTarget(_PushTarget target) {
    if (target.type == 'rematch') {
      openedRematchId.value = target.id;
    } else {
      openedChallengeId.value = target.id;
    }
  }

  Future<void> _registerToken(String token) async {
    if (!enabled.value ||
        !SocialApiClient.instance.configured ||
        token.isEmpty) {
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

class _ConsumableValueNotifier<T> extends ValueNotifier<T?> {
  _ConsumableValueNotifier() : super(null);

  bool _clearScheduled = false;

  @override
  T? get value {
    final current = super.value;
    if (current != null && !_clearScheduled) {
      _clearScheduled = true;
      scheduleMicrotask(() {
        _clearScheduled = false;
        if (identical(super.value, current)) super.value = null;
      });
    }
    return current;
  }

  @override
  set value(T? next) {
    _clearScheduled = false;
    super.value = next;
  }
}

class _PushTarget {
  const _PushTarget({
    required this.type,
    required this.id,
    this.defaultTitle = 'Online invitation',
    this.defaultBody = 'Open Sudoku Duel to respond.',
  });

  final String type;
  final String id;
  final String defaultTitle;
  final String defaultBody;
}
