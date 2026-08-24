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

enum PushNotificationDestinationType {
  challenge,
  rematch,
  room,
  social,
  informational,
}

@immutable
class PushNotificationDestination {
  const PushNotificationDestination({
    required this.type,
    required this.id,
    required this.defaultTitle,
    required this.defaultBody,
  });

  final PushNotificationDestinationType type;
  final String id;
  final String defaultTitle;
  final String defaultBody;

  String get payload => '${type.name}:$id';
}

@visibleForTesting
PushNotificationDestination? parsePushNotificationDestination(
  Map<String, dynamic> data,
) {
  final messageType = data['type']?.toString();
  if (messageType == 'challenge_response') {
    final status = data['status']?.toString();
    final roomId = data['roomId']?.toString();
    if (status == 'accepted' && roomId != null && roomId.isNotEmpty) {
      return PushNotificationDestination(
        type: PushNotificationDestinationType.room,
        id: roomId,
        defaultTitle: 'Challenge accepted',
        defaultBody: 'Your opponent accepted. The duel room is ready.',
      );
    }
    final challengeId = data['challengeId']?.toString() ?? 'challenge';
    return PushNotificationDestination(
      type: PushNotificationDestinationType.informational,
      id: challengeId,
      defaultTitle: status == 'declined'
          ? 'Challenge declined'
          : status == 'cancelled'
          ? 'Challenge cancelled'
          : 'Challenge updated',
      defaultBody: status == 'declined'
          ? 'Your opponent declined the Sudoku challenge.'
          : status == 'cancelled'
          ? 'The pending Sudoku challenge was cancelled.'
          : 'Your Sudoku challenge status changed.',
    );
  }

  if (messageType == 'friend_request') {
    final requesterId = data['requesterPublicId']?.toString();
    if (requesterId != null && requesterId.isNotEmpty) {
      return PushNotificationDestination(
        type: PushNotificationDestinationType.social,
        id: requesterId,
        defaultTitle: 'New friend request',
        defaultBody: 'A player sent you a friend request.',
      );
    }
  }

  if (messageType == 'friend_response') {
    final playerId = data['playerPublicId']?.toString();
    final status = data['status']?.toString();
    if (playerId != null && playerId.isNotEmpty) {
      return PushNotificationDestination(
        type: PushNotificationDestinationType.social,
        id: playerId,
        defaultTitle: status == 'accepted'
            ? 'Friend request accepted'
            : 'Friend request updated',
        defaultBody: status == 'accepted'
            ? 'Your friend request was accepted.'
            : 'Your friend request was updated.',
      );
    }
  }

  final rematchId = data['rematchId']?.toString();
  if (rematchId != null && rematchId.isNotEmpty) {
    return PushNotificationDestination(
      type: PushNotificationDestinationType.rematch,
      id: rematchId,
      defaultTitle: 'Rematch invitation',
      defaultBody:
          'A player wants to play again. Open Sudoku Duel to respond.',
    );
  }

  final challengeId = data['challengeId']?.toString();
  if (challengeId != null && challengeId.isNotEmpty) {
    return PushNotificationDestination(
      type: PushNotificationDestinationType.challenge,
      id: challengeId,
      defaultTitle: 'New Sudoku challenge',
      defaultBody: 'A player challenged you. Open Sudoku Duel to respond.',
    );
  }
  return null;
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
  final ValueNotifier<bool> userDisabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> permissionGranted = ValueNotifier<bool>(false);
  final ValueNotifier<String?> lastRegistrationError = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<String?> openedRoomId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> openedChallengeId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> openedRematchId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> openedSocialId = ValueNotifier<String?>(null);

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  Future<void>? _initialization;

  bool get configured => FirebaseRuntimeConfig.configured;

  bool get hasPendingNavigation =>
      openedRoomId.value?.isNotEmpty == true ||
      openedChallengeId.value?.isNotEmpty == true ||
      openedRematchId.value?.isNotEmpty == true ||
      openedSocialId.value?.isNotEmpty == true;

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

      final savedEnabled = await _preferences.getBool(_enabledKey);
      userDisabled.value = savedEnabled == false;

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
        (token) => unawaited(_registerToken(token)),
      );

      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) _handleOpenedMessage(initialMessage);

      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      final authorized = _isAuthorized(settings.authorizationStatus);
      permissionGranted.value = authorized;
      enabled.value = (savedEnabled ?? authorized) && authorized;
      if (savedEnabled == null && authorized) {
        await _preferences.setBool(_enabledKey, true);
      }
      if (enabled.value) await _registerCurrentToken();

      initialized.value = true;
    } catch (error, stackTrace) {
      initialized.value = false;
      lastRegistrationError.value = error.toString();
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
        userDisabled.value = true;
        lastRegistrationError.value = 'Notification permission was denied.';
        await _preferences.setBool(_enabledKey, false);
        return false;
      }

      enabled.value = true;
      userDisabled.value = false;
      lastRegistrationError.value = null;
      await _preferences.setBool(_enabledKey, true);
      return _registerCurrentToken();
    } catch (error, stackTrace) {
      lastRegistrationError.value = error.toString();
      debugPrint('Challenge notification permission failed: $error');
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
      return false;
    }
  }

  Future<bool> refreshRegistration() async {
    if (!configured) return false;
    if (!initialized.value) await initialize();
    if (!initialized.value || userDisabled.value) return false;

    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final allowed = _isAuthorized(settings.authorizationStatus);
    permissionGranted.value = allowed;
    if (!allowed) {
      enabled.value = false;
      return false;
    }
    enabled.value = true;
    return _registerCurrentToken();
  }

  Future<void> disableChallengeNotifications() async {
    if (!configured) return;
    if (!initialized.value) await initialize();

    enabled.value = false;
    userDisabled.value = true;
    lastRegistrationError.value = null;
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
    final target = parsePushNotificationDestination(message.data);
    if (target == null) return;

    // Actionable social notifications should move an already-open app directly
    // into the invitation/ready/social flow. Background and terminated apps
    // continue to route when the user taps the system notification.
    if (target.type != PushNotificationDestinationType.informational) {
      _openTarget(target);
      return;
    }

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
        payload: target.payload,
      );
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final target = parsePushNotificationDestination(message.data);
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
    final typeName = payload.substring(0, separator);
    final id = payload.substring(separator + 1);
    if (id.isEmpty) return;
    final type = PushNotificationDestinationType.values.where(
      (value) => value.name == typeName,
    );
    if (type.isEmpty) return;
    _openTarget(
      PushNotificationDestination(
        type: type.first,
        id: id,
        defaultTitle: 'Online invitation',
        defaultBody: 'Open Sudoku Duel to continue.',
      ),
    );
  }

  void _openTarget(PushNotificationDestination target) {
    switch (target.type) {
      case PushNotificationDestinationType.room:
        openedRoomId.value = target.id;
      case PushNotificationDestinationType.rematch:
        openedRematchId.value = target.id;
      case PushNotificationDestinationType.challenge:
        openedChallengeId.value = target.id;
      case PushNotificationDestinationType.social:
        openedSocialId.value = target.id;
      case PushNotificationDestinationType.informational:
        break;
    }
  }

  Future<bool> _registerCurrentToken() async {
    final token = await _loadMessagingToken();
    if (token == null || token.isEmpty) {
      lastRegistrationError.value = 'FCM registration token is unavailable.';
      return false;
    }
    return _registerToken(token);
  }

  Future<String?> _loadMessagingToken() async {
    if (!kIsWeb && Platform.isIOS) {
      for (var attempt = 0; attempt < 12; attempt++) {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    return FirebaseMessaging.instance.getToken();
  }

  Future<bool> _registerToken(String token) async {
    if (!enabled.value ||
        !SocialApiClient.instance.configured ||
        token.isEmpty) {
      return false;
    }
    final platform = !kIsWeb && Platform.isIOS ? 'ios' : 'android';
    try {
      await SocialApiClient.instance.registerDeviceToken(
        token: token,
        platform: platform,
      );
      lastRegistrationError.value = null;
      return true;
    } on SocialApiException catch (error, stackTrace) {
      lastRegistrationError.value = error.message;
      debugPrint('Push token registration failed: $error');
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
      return false;
    } catch (error, stackTrace) {
      lastRegistrationError.value = error.toString();
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
      return false;
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
