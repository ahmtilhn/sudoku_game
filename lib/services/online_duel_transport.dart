import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'online_duel_models.dart';
import 'social_api_client.dart';

abstract class OnlineDuelTransport {
  Stream<OnlineDuelEvent> get events;
  void send(Map<String, Object?> message);
  Future<void> close();
}

class WebSocketOnlineDuelTransport implements OnlineDuelTransport {
  WebSocketOnlineDuelTransport._(this._channel) {
    _subscription = _channel.stream.listen(
      (message) {
        try {
          final decoded = jsonDecode(message.toString()) as Map;
          _events.add(
            OnlineDuelEvent.fromJson(decoded.cast<String, dynamic>()),
          );
        } catch (error, stackTrace) {
          _events.addError(error, stackTrace);
        }
      },
      onError: _events.addError,
      onDone: _events.close,
    );
  }

  final WebSocketChannel _channel;
  final StreamController<OnlineDuelEvent> _events =
      StreamController<OnlineDuelEvent>.broadcast();
  late final StreamSubscription<dynamic> _subscription;

  static Future<WebSocketOnlineDuelTransport> connect(String roomId) async {
    if (!SocialApiClient.instance.configured) {
      throw const SocialApiException(
        0,
        'The social backend URL is not configured.',
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const SocialApiException(401, 'A Firebase session is required.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const SocialApiException(
        401,
        'Unable to obtain a Firebase ID token.',
      );
    }
    final uri = SocialApiClient.instance.websocketUri(
      '/v1/rooms/$roomId/connect',
    );
    final appCheckToken = await _appCheckToken();
    final channel = IOWebSocketChannel.connect(
      uri,
      headers: <String, String>{
        'authorization': 'Bearer $token',
        ...?appCheckToken == null
            ? null
            : <String, String>{'x-firebase-appcheck': appCheckToken},
      },
    );
    return WebSocketOnlineDuelTransport._(channel);
  }

  @override
  Stream<OnlineDuelEvent> get events => _events.stream;

  @override
  void send(Map<String, Object?> message) {
    _channel.sink.add(jsonEncode(message));
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _channel.sink.close();
    await _events.close();
  }
}

Future<String?> _appCheckToken() async {
  try {
    final token = await FirebaseAppCheck.instance.getToken(false);
    return token == null || token.isEmpty ? null : token;
  } catch (_) {
    return null;
  }
}

class FakeOnlineDuelTransport implements OnlineDuelTransport {
  final StreamController<OnlineDuelEvent> _events =
      StreamController<OnlineDuelEvent>.broadcast();
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];

  @override
  Stream<OnlineDuelEvent> get events => _events.stream;

  void emit(OnlineDuelEvent event) => _events.add(event);

  @override
  void send(Map<String, Object?> message) => sent.add(message);

  @override
  Future<void> close() => _events.close();
}
