import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class PreferencesBackend {
  Future<int?> getInt(String key);

  Future<bool?> getBool(String key);

  Future<String?> getString(String key);

  Future<void> setInt(String key, int value);

  Future<void> setBool(String key, bool value);

  Future<void> setString(String key, String value);

  Future<void> remove(String key);
}

class SharedPreferencesBackend implements PreferencesBackend {
  SharedPreferencesBackend() : _preferences = SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<int?> getInt(String key) => _preferences.getInt(key);

  @override
  Future<bool?> getBool(String key) => _preferences.getBool(key);

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setInt(String key, int value) => _preferences.setInt(key, value);

  @override
  Future<void> setBool(String key, bool value) =>
      _preferences.setBool(key, value);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<void> remove(String key) => _preferences.remove(key);
}

class MemoryPreferencesBackend implements PreferencesBackend {
  MemoryPreferencesBackend([Map<String, Object>? initialValues])
    : _values = <String, Object>{...?initialValues};

  final Map<String, Object> _values;

  @override
  Future<int?> getInt(String key) async => _values[key] as int?;

  @override
  Future<bool?> getBool(String key) async => _values[key] as bool?;

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<void> setInt(String key, int value) async {
    _values[key] = value;
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

class LevelProgress {
  const LevelProgress({
    required this.stars,
    required this.bestSeconds,
    required this.bestMistakes,
  });

  final int stars;
  final int bestSeconds;
  final int bestMistakes;

  Map<String, Object> toJson() => <String, Object>{
    'stars': stars,
    'bestSeconds': bestSeconds,
    'bestMistakes': bestMistakes,
  };

  factory LevelProgress.fromJson(Map<String, dynamic> json) {
    return LevelProgress(
      stars: (json['stars'] as num?)?.toInt() ?? 0,
      bestSeconds: (json['bestSeconds'] as num?)?.toInt() ?? 0,
      bestMistakes: (json['bestMistakes'] as num?)?.toInt() ?? 0,
    );
  }
}

class LocalProgressStore extends ChangeNotifier {
  LocalProgressStore._(this._preferences);

  static const _progressKey = 'career_progress_v1';
  static const _themeKey = 'theme_mode_v1';
  static const _highContrastKey = 'high_contrast_v1';
  static const _tutorialKey = 'tutorial_complete_v1';
  static const _coinsKey = 'career_coins_v1';
  static const _hintsKey = 'hint_inventory_v1';

  static const int initialCoins = 100;
  static const int initialHints = 3;

  final PreferencesBackend _preferences;
  final Map<String, LevelProgress> _progress = <String, LevelProgress>{};

  ThemeMode themeMode = ThemeMode.system;
  bool highContrast = false;
  bool tutorialCompleted = false;
  int coins = initialCoins;
  int hints = initialHints;

  static Future<LocalProgressStore> create() async {
    final store = LocalProgressStore._(SharedPreferencesBackend());
    await store._load();
    return store;
  }

  static Future<LocalProgressStore> createInMemory({
    Map<String, Object>? initialValues,
  }) async {
    final store = LocalProgressStore._(MemoryPreferencesBackend(initialValues));
    await store._load();
    return store;
  }

  int get completedLevelCount => _progress.length;

  bool isCompleted(String puzzleId) => _progress.containsKey(puzzleId);

  LevelProgress? progressFor(String puzzleId) => _progress[puzzleId];

  Future<void> recordResult({
    required String puzzleId,
    required int seconds,
    required int mistakes,
    required int hints,
  }) async {
    final stars = _calculateStars(mistakes: mistakes, hints: hints);
    final previous = _progress[puzzleId];
    _progress[puzzleId] = LevelProgress(
      stars: previous == null
          ? stars
          : stars > previous.stars
          ? stars
          : previous.stars,
      bestSeconds: previous == null || seconds < previous.bestSeconds
          ? seconds
          : previous.bestSeconds,
      bestMistakes: previous == null || mistakes < previous.bestMistakes
          ? mistakes
          : previous.bestMistakes,
    );
    await _saveProgress();
    notifyListeners();
  }

  Future<bool> spendCoins(int amount) async {
    if (amount <= 0 || coins < amount) return false;
    coins -= amount;
    await _preferences.setInt(_coinsKey, coins);
    notifyListeners();
    return true;
  }

  Future<void> addCoins(int amount) async {
    if (amount <= 0) return;
    coins += amount;
    await _preferences.setInt(_coinsKey, coins);
    notifyListeners();
  }

  Future<bool> consumeHint() async {
    if (hints <= 0) return false;
    hints--;
    await _preferences.setInt(_hintsKey, hints);
    notifyListeners();
    return true;
  }

  Future<void> addHints(int amount) async {
    if (amount <= 0) return;
    hints += amount;
    await _preferences.setInt(_hintsKey, hints);
    notifyListeners();
  }

  Future<bool> purchaseHint({required int coinCost}) async {
    if (coinCost <= 0 || coins < coinCost) return false;
    coins -= coinCost;
    hints++;
    await Future.wait<void>(<Future<void>>[
      _preferences.setInt(_coinsKey, coins),
      _preferences.setInt(_hintsKey, hints),
    ]);
    notifyListeners();
    return true;
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    await _preferences.setInt(_themeKey, value.index);
    notifyListeners();
  }

  Future<void> setHighContrast(bool value) async {
    highContrast = value;
    await _preferences.setBool(_highContrastKey, value);
    notifyListeners();
  }

  Future<void> markTutorialComplete() async {
    tutorialCompleted = true;
    await _preferences.setBool(_tutorialKey, true);
    notifyListeners();
  }

  Future<void> clearProgress() async {
    _progress.clear();
    await _preferences.remove(_progressKey);
    notifyListeners();
  }

  Future<void> _load() async {
    final themeIndex = await _preferences.getInt(_themeKey);
    if (themeIndex != null &&
        themeIndex >= 0 &&
        themeIndex < ThemeMode.values.length) {
      themeMode = ThemeMode.values[themeIndex];
    }
    highContrast = await _preferences.getBool(_highContrastKey) ?? false;
    tutorialCompleted = await _preferences.getBool(_tutorialKey) ?? false;
    coins = await _preferences.getInt(_coinsKey) ?? initialCoins;
    hints = await _preferences.getInt(_hintsKey) ?? initialHints;

    final raw = await _preferences.getString(_progressKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          _progress[entry.key] = LevelProgress.fromJson(value);
        } else if (value is Map) {
          _progress[entry.key] = LevelProgress.fromJson(
            value.map((key, item) => MapEntry(key.toString(), item)),
          );
        }
      }
    } on FormatException {
      _progress.clear();
    }
  }

  Future<void> _saveProgress() {
    final encoded = jsonEncode(
      _progress.map((key, value) => MapEntry(key, value.toJson())),
    );
    return _preferences.setString(_progressKey, encoded);
  }

  static int _calculateStars({required int mistakes, required int hints}) {
    if (mistakes == 0 && hints == 0) {
      return 3;
    }
    if (mistakes <= 2 && hints <= 1) {
      return 2;
    }
    return 1;
  }
}
