import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../localization/ux_copy.dart';

class UserSafeError {
  const UserSafeError._();

  static String message(
    BuildContext context,
    Object? error, {
    String? fallback,
  }) {
    if (error != null) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          library: 'sudoku_game',
          context: ErrorDescription('while preparing a user-safe error'),
          silent: kReleaseMode,
        ),
      );
    }

    if (error is TimeoutException || error is SocketException) {
      return UxCopy.connectionError(context);
    }

    final rawError = error?.toString().trim() ?? '';
    final normalized = rawError.toLowerCase();
    if (_containsAny(normalized, const <String>[
      'timeout',
      'timed out',
      'socket',
      'network',
      'connection',
      'failed host lookup',
      'clientexception',
    ])) {
      return UxCopy.connectionError(context);
    }
    if (_containsAny(normalized, const <String>[
      '401',
      '403',
      'unauthorized',
      'permission-denied',
      'authentication',
      'firebase',
      'token',
      'account_link',
    ])) {
      final safeMessage = UxCopy.accountError(context);
      if (_shouldExposePlayGamesDiagnostics(normalized) && rawError.isNotEmpty) {
        return '$safeMessage\n\nDiagnostic:\n$rawError';
      }
      return safeMessage;
    }
    if (_containsAny(normalized, const <String>[
      '429',
      '500',
      '502',
      '503',
      '504',
      'server',
      'backend',
      'unexpected response',
      'invalid response',
    ])) {
      return UxCopy.serverBusy(context);
    }
    return fallback ?? UxCopy.genericError(context);
  }

  static bool _shouldExposePlayGamesDiagnostics(String value) {
    return _containsAny(value, const <String>[
      'play games',
      'play_games',
      'playgamesproject=',
      'certificatesha1=',
      'installer=',
      'apistatuscode=',
      'account_link_failed',
      'server_auth_code',
      'authentication_failed:',
      'not_authenticated:',
    ]);
  }

  static bool _containsAny(String value, List<String> terms) {
    for (final term in terms) {
      if (value.contains(term)) return true;
    }
    return false;
  }
}
