import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'online_duel_models.dart';
import 'social_api_client.dart';

enum OnlineDuelConnectionState {
  connecting,
  connected,
  reconnecting,
  resyncing,
  failed,
  closed,
}

abstract class OnlineDuelTransport {
  Stream<OnlineDuelEvent> get events;
  Stream<OnlineDuelConnectionState> get connectionStates;
  OnlineDuelConnectionState get connectionState;
  void send(Map<String, Object?> message);
  Future<void> reconnectNow();
  Future<void> close();
}

class WebSocketOnlineDuelTransport implements OnlineDuelTransport {
  WebSocketOnlineDuelTransport._(this._roomId);

  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _appCheckTimeout = Duration(seconds: 5);
  static const int _maxQueuedMessages = 24;
  static const int _maxReconnectAttemptsBeforeFailedState = 8;

  final String _roomId;
  final StreamController<OnlineDuelEvent> _events =
      StreamController<OnlineDuelEvent>.broadcast();
  final StreamController<OnlineDuelConnectionState> _connectionStates =
      StreamController<OnlineDuelConnectionState>.broadcast();
  final List<Map<String, Object?>> _outboundQueue =
      <Map<String, Object?>>[];

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Future<void>? _connecting;
  bool _closed = false;
  int _reconnectAttempt = 0;
  OnlineDuelConnectionState _connectionState =
      OnlineDuelConnectionState.connecting;

  static Future<WebSocketOnlineDuelTransport> connect(String roomId) async {
    final transport = WebSocketOnlineDuelTransport._(roomId);
    await transport._connect(initial: true);
    return transport;
  }

  @override
  Stream<OnlineDuelEvent> get events => _events.stream;

  @override
  Stream<OnlineDuelConnectionState> get connectionStates =>
      _connectionStates.stream;

  @override
  OnlineDuelConnectionState get connectionState => _connectionState;

  @override
  void send(Map<String, Object?> message) {
    if (_closed) return;
    final encoded = jsonEncode(message);
    final channel = _channel;
    if (channel != null &&
        (_connectionState == OnlineDuelConnectionState.connected ||
            _connectionState == OnlineDuelConnectionState.resyncing)) {
      try {
        channel.sink.add(encoded);
        return;
      } catch (_) {
        _queue(message);
        _handleDisconnect();
        return;
      }
    }
    _queue(message);
    unawaited(reconnectNow());
  }

  @override
  Future<void> reconnectNow() async {
    if (_closed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _connect(initial: false);
  }

  Future<void> _connect({required bool initial}) {
    if (_closed) return Future<void>.value();
    final existing = _connecting;
    if (existing != null) return existing;

    final operation = _openSocket(initial: initial);
    _connecting = operation;
    return operation.whenComplete(() {
      if (identical(_connecting, operation)) _connecting = null;
    });
  }

  Future<void> _openSocket({required bool initial}) async {
    _setConnectionState(
      initial
          ? OnlineDuelConnectionState.connecting
          : OnlineDuelConnectionState.reconnecting,
    );

    try {
      await _disposeSocket();
      final credentials = await _credentials();
      final uri = SocialApiClient.instance.websocketUri(
        '/v1/rooms/$_roomId/connect',
      );
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: onlineDuelHeadersForTest(
          firebaseIdToken: credentials.firebaseIdToken,
          appCheckToken: credentials.appCheckToken,
        ),
      );
      await channel.ready.timeout(_connectTimeout);
      if (_closed) {
        await channel.sink.close();
        return;
      }

      _channel = channel;
      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (Object error, StackTrace stackTrace) {
          if (!_events.isClosed) _events.addError(error, stackTrace);
          _handleDisconnect();
        },
        onDone: _handleDisconnect,
        cancelOnError: false,
      );
      _reconnectAttempt = 0;
      _setConnectionState(OnlineDuelConnectionState.resyncing);
      _flushQueue();
    } catch (error, stackTrace) {
      if (initial) {
        await _disposeSocket();
        rethrow;
      }
      if (!_events.isClosed) _events.addError(error, stackTrace);
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is! Map) {
        throw const FormatException('Online duel event must be a JSON object.');
      }
      final event = OnlineDuelEvent.fromJson(
        decoded.cast<String, dynamic>(),
      );
      if (event.type == 'connected' ||
          event.type == 'snapshot' ||
          event.type == 'match_started' ||
          event.type == 'game_started') {
        _setConnectionState(OnlineDuelConnectionState.connected);
      }
      if (!_events.isClosed) _events.add(event);
    } catch (error, stackTrace) {
      if (!_events.isClosed) _events.addError(error, stackTrace);
    }
  }

  void _handleDisconnect() {
    if (_closed) return;
    unawaited(_disposeSocket());
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed || _reconnectTimer != null) return;
    _reconnectAttempt++;
    if (_reconnectAttempt >= _maxReconnectAttemptsBeforeFailedState) {
      _setConnectionState(OnlineDuelConnectionState.failed);
    } else {
      _setConnectionState(OnlineDuelConnectionState.reconnecting);
    }
    final delay = onlineDuelReconnectDelay(_reconnectAttempt);
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_connect(initial: false));
    });
  }

  void _queue(Map<String, Object?> message) {
    final type = message['type']?.toString();
    if (type == 'request_snapshot') {
      _outboundQueue.removeWhere(
        (queued) => queued['type']?.toString() == 'request_snapshot',
      );
    }
    _outboundQueue.add(Map<String, Object?>.from(message));
    if (_outboundQueue.length > _maxQueuedMessages) {
      _outboundQueue.removeAt(0);
    }
  }

  void _flushQueue() {
    final channel = _channel;
    if (channel == null || _closed) return;
    final queued = List<Map<String, Object?>>.from(_outboundQueue);
    _outboundQueue.clear();
    for (final message in queued) {
      try {
        channel.sink.add(jsonEncode(message));
      } catch (_) {
        _queue(message);
        _handleDisconnect();
        break;
      }
    }
  }

  Future<({String firebaseIdToken, String? appCheckToken})>
  _credentials() async {
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

    final String? token;
    try {
      token = await user.getIdToken(true).timeout(_connectTimeout);
    } on TimeoutException {
      throw const SocialApiException(
        0,
        'Firebase session refresh timed out. Please try again.',
      );
    } on FirebaseAuthException catch (error) {
      throw SocialApiException(
        401,
        error.message ?? 'Unable to refresh the Firebase session.',
      );
    }
    if (token == null || token.isEmpty) {
      throw const SocialApiException(
        401,
        'Unable to obtain a Firebase ID token.',
      );
    }
    return (
      firebaseIdToken: token,
      appCheckToken: await _appCheckToken(forceRefresh: true),
    );
  }

  void _setConnectionState(OnlineDuelConnectionState state) {
    if (_connectionState == state) return;
    _connectionState = state;
    if (!_connectionStates.isClosed) _connectionStates.add(state);
  }

  Future<void> _disposeSocket() async {
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await subscription?.cancel();
    try {
      await channel?.sink.close();
    } catch (_) {
      // Socket may already be closed by the remote endpoint.
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _outboundQueue.clear();
    await _disposeSocket();
    _setConnectionState(OnlineDuelConnectionState.closed);
    if (!_events.isClosed) await _events.close();
    if (!_connectionStates.isClosed) await _connectionStates.close();
  }
}

Duration onlineDuelReconnectDelay(int attempt) {
  final exponent = math.max(0, math.min(attempt - 1, 4));
  final seconds = math.min(15, 1 << exponent);
  return Duration(seconds: seconds);
}

Map<String, String> onlineDuelHeadersForTest({
  required String firebaseIdToken,
  String? appCheckToken,
}) {
  return <String, String>{
    'authorization': 'Bearer $firebaseIdToken',
    if (appCheckToken != null && appCheckToken.isNotEmpty)
      'x-firebase-appcheck': appCheckToken,
  };
}

Future<String?> _appCheckToken({bool forceRefresh = false}) async {
  try {
    final token = await FirebaseAppCheck.instance
        .getToken(forceRefresh)
        .timeout(WebSocketOnlineDuelTransport._appCheckTimeout);
    return token == null || token.isEmpty ? null : token;
  } catch (_) {
    return null;
  }
}

class FakeOnlineDuelTransport implements OnlineDuelTransport {
  final StreamController<OnlineDuelEvent> _events =
      StreamController<OnlineDuelEvent>.broadcast();
  final StreamController<OnlineDuelConnectionState> _connectionStates =
      StreamController<OnlineDuelConnectionState>.broadcast();
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  OnlineDuelConnectionState _state = OnlineDuelConnectionState.connected;

  @override
  Stream<OnlineDuelEvent> get events => _events.stream;

  @override
  Stream<OnlineDuelConnectionState> get connectionStates =>
      _connectionStates.stream;

  @override
  OnlineDuelConnectionState get connectionState => _state;

  void emit(OnlineDuelEvent event) => _events.add(event);

  void emitConnectionState(OnlineDuelConnectionState state) {
    _state = state;
    _connectionStates.add(state);
  }

  @override
  void send(Map<String, Object?> message) => sent.add(message);

  @override
  Future<void> reconnectNow() async {
    emitConnectionState(OnlineDuelConnectionState.resyncing);
  }

  @override
  Future<void> close() async {
    _state = OnlineDuelConnectionState.closed;
    await _events.close();
    await _connectionStates.close();
  }
}
