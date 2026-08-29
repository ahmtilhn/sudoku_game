import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../localization/app_strings.dart';
import 'firebase_runtime_config.dart';
import 'firebase_services.dart';
import 'notification_platform_service.dart';
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
    required this.defaultTitleKey,
    required this.defaultBodyKey,
  });

  final PushNotificationDestinationType type;
  final String id;
  final String defaultTitleKey;
  final String defaultBodyKey;

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
        defaultTitleKey: 'push_challenge_accepted_title',
        defaultBodyKey: 'push_challenge_accepted_body',
      );
    }
    final challengeId = data['challengeId']?.toString() ?? 'challenge';
    return PushNotificationDestination(
      type: PushNotificationDestinationType.informational,
      id: challengeId,
      defaultTitleKey: status == 'declined'
          ? 'push_challenge_declined_title'
          : status == 'cancelled'
          ? 'push_challenge_cancelled_title'
          : 'push_challenge_updated_title',
      defaultBodyKey: status == 'declined'
          ? 'push_challenge_declined_body'
          : status == 'cancelled'
          ? 'push_challenge_cancelled_body'
          : 'push_challenge_updated_body',
    );
  }

  if (messageType == 'friend_request') {
    final requesterId = data['requesterPublicId']?.toString();
    if (requesterId != null && requesterId.isNotEmpty) {
      return PushNotificationDestination(
        type: PushNotificationDestinationType.social,
        id: requesterId,
        defaultTitleKey: 'push_friend_request_title',
        defaultBodyKey: 'push_friend_request_body',
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
        defaultTitleKey: status == 'accepted'
            ? 'push_friend_accepted_title'
            : status == 'declined'
            ? 'push_friend_declined_title'
            : 'push_friend_updated_title',
        defaultBodyKey: status == 'accepted'
            ? 'push_friend_accepted_body'
            : status == 'declined'
            ? 'push_friend_declined_body'
            : 'push_friend_updated_body',
      );
    }
  }

  final rematchId = data['rematchId']?.toString();
  if (rematchId != null && rematchId.isNotEmpty) {
    return PushNotificationDestination(
      type: PushNotificationDestinationType.rematch,
      id: rematchId,
      defaultTitleKey: 'push_rematch_title',
      defaultBodyKey: 'push_rematch_body',
    );
  }

  final challengeId = data['challengeId']?.toString();
  if (challengeId != null && challengeId.isNotEmpty) {
    return PushNotificationDestination(
      type: PushNotificationDestinationType.challenge,
      id: challengeId,
      defaultTitleKey: 'push_challenge_title',
      defaultBodyKey: 'push_challenge_body',
    );
  }
  return null;
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const String _challengeChannelId = 'online_challenges';
  static const String _enabledKey = 'challenge_push_enabled_v1';
  static const String _safeRegistrationError =
      'Notification setup could not be completed. Please try again.';

  final NotificationPlatformService _platform =
      NotificationPlatformService.instance;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  final ValueNotifier<bool> initialized = ValueNotifier<bool>(false);
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> userDisabled = ValueNotifier<bool>(true);
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
  bool _platformPayloadListenerAttached = false;
  AppStrings? _strings;

  bool get configured => FirebaseRuntimeConfig.configured;

  bool get hasPendingNavigation =>
      openedRoomId.value?.isNotEmpty == true ||
      openedChallengeId.value?.isNotEmpty == true ||
      openedRematchId.value?.isNotEmpty == true ||
      openedSocialId.value?.isNotEmpty == true;

  /// Kept for compatibility with older navigation gates. Foreground delivery
  /// no longer opens social UI automatically; only an explicit notification
  /// tap creates a navigation destination.
  void setAutomaticSocialUiAllowed(bool value) {
    // Intentionally no-op.
  }

  Future<void> initialize() {
    if (!configured || initialized.value) return Future<void>.value();
    return _initialization ??= _initializeOnce().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initializeOnce() async {
    try {
      await FirebaseRuntimeConfig.initializeIfConfigured();
      _strings ??= await AppStrings.load();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final signedIn = await _ensureAnonymousSession();
      if (!signedIn) return;

      final savedEnabled = await _preferences.getBool(_enabledKey);
      userDisabled.value = savedEnabled != true;

      await _initializeLocalNotifications();
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: false,
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

      // OS permission is shared by all notification features. Do not interpret
      // a permission granted for daily reminders as consent for online pushes.
      enabled.value = savedEnabled == true && authorized;
      if (enabled.value) await _registerCurrentToken();

      initialized.value = true;
    } catch (error, stackTrace) {
      initialized.value = false;
      lastRegistrationError.value = _safeRegistrationError;
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
        badge: false,
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
        lastRegistrationError.value = _localized(
          'notification_permission_denied',
        );
        await _preferences.setBool(_enabledKey, false);
        return false;
      }

      enabled.value = true;
      userDisabled.value = false;
      lastRegistrationError.value = null;
      await _preferences.setBool(_enabledKey, true);
      return await _registerCurrentToken();
    } catch (error, stackTrace) {
      lastRegistrationError.value = _safeRegistrationError;
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
    return await _registerCurrentToken();
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
    await _platform.initialize();
    if (!_platformPayloadListenerAttached) {
      _platform.openedPayload.addListener(_handlePlatformPayload);
      _platformPayloadListenerAttached = true;
    }
    _handlePlatformPayload();

    if (!kIsWeb && Platform.isAndroid) {
      await _platform.plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            AndroidNotificationChannel(
              _challengeChannelId,
              _localized('online_challenges_channel_name'),
              description: _localized('online_challenges_channel_description'),
              importance: Importance.high,
            ),
          );
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (!enabled.value) return;
    final target = parsePushNotificationDestination(message.data);
    if (target == null) return;

    // Receiving a push is not the same action as opening it. Foreground pushes
    // are presented to the user and only their tap is allowed to navigate.
    await _showForegroundSystemNotification(target);
  }

  Future<void> _showForegroundSystemNotification(
    PushNotificationDestination target,
  ) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    await _platform.plugin.show(
      id: target.id.hashCode & 0x7fffffff,
      title: _localized(target.defaultTitleKey),
      body: _localized(target.defaultBodyKey),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _challengeChannelId,
          _localized('online_challenges_channel_name'),
          channelDescription: _localized(
            'online_challenges_channel_description',
          ),
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          threadIdentifier: 'online-challenges',
          presentBadge: false,
        ),
      ),
      payload: target.payload,
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final target = parsePushNotificationDestination(message.data);
    if (target == null) return;
    _openTarget(target);
  }

  void _handlePlatformPayload() {
    final payload = _platform.openedPayload.value;
    if (payload == null || payload.isEmpty || payload == 'daily-reminder') {
      return;
    }
    if (_handleLocalPayload(payload)) {
      _platform.consumePayload(payload);
    }
  }

  bool _handleLocalPayload(String payload) {
    final separator = payload.indexOf(':');
    if (separator <= 0) return false;
    final typeName = payload.substring(0, separator);
    final id = payload.substring(separator + 1);
    if (id.isEmpty) return false;
    final type = PushNotificationDestinationType.values.where(
      (value) => value.name == typeName,
    );
    if (type.isEmpty) return false;
    _openTarget(
      PushNotificationDestination(
        type: type.first,
        id: id,
        defaultTitleKey: 'push_online_invitation_title',
        defaultBodyKey: 'push_online_invitation_body',
      ),
    );
    return true;
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
      lastRegistrationError.value = _safeRegistrationError;
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
      lastRegistrationError.value = _safeRegistrationError;
      debugPrint('Push token registration failed: $error');
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
      return false;
    } catch (error, stackTrace) {
      lastRegistrationError.value = _safeRegistrationError;
      await FirebaseServices.instance.recordNonFatal(error, stackTrace);
      return false;
    }
  }

  String _localized(String key) =>
      _strings?.text(key) ?? AppStrings.english[key] ?? key;

  bool _isAuthorized(AuthorizationStatus status) {
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _openedSubscription?.cancel();
    if (_platformPayloadListenerAttached) {
      _platform.openedPayload.removeListener(_handlePlatformPayload);
      _platformPayloadListenerAttached = false;
    }
  }
}
