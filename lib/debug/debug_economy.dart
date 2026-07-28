import 'package:flutter/foundation.dart';

const int debugUnlimitedCoinBalance = 999999999;

bool get debugUnlimitedCoinsEnabled =>
    kDebugMode &&
    !const bool.fromEnvironment(
      'SUDOKU_DISABLE_DEBUG_UNLIMITED_COINS',
      defaultValue: false,
    );
