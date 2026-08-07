import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../debug/debug_economy.dart';
import '../domain/sudoku_variant.dart';

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
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }
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
    this.bestHints = 0,
    this.rewardClaimed = false,
  });

  final int stars;
  final int bestSeconds;
  final int bestMistakes;
  final int bestHints;
  final bool rewardClaimed;

  Map<String, Object> toJson() => <String, Object>{
    'stars': stars,
    'bestSeconds': bestSeconds,
    'bestMistakes': bestMistakes,
    'bestHints': bestHints,
    'rewardClaimed': rewardClaimed,
  };

  factory LevelProgress.fromJson(Map<String, dynamic> json) {
    return LevelProgress(
      stars: (json['stars'] as num?)?.toInt() ?? 0,
      bestSeconds: (json['bestSeconds'] as num?)?.toInt() ?? 0,
      bestMistakes: (json['bestMistakes'] as num?)?.toInt() ?? 0,
      bestHints: (json['bestHints'] as num?)?.toInt() ?? 0,
      rewardClaimed: json['rewardClaimed'] == true,
    );
  }
}

class LocalProgressStore extends ChangeNotifier {
  LocalProgressStore._(this._preferences, {required this.unlimitedCoins});

  static const _progressKey = 'career_progress_v2';
  static const _legacyProgressKey = 'career_progress_v1';
  static const _themeKey = 'theme_mode_v1';
  static const _highContrastKey = 'high_contrast_v1';
  static const _tutorialKey = 'tutorial_complete_v1';
  static const _coinsKey = 'career_coins_v1';
  static const _hintsKey = 'hint_inventory_v1';

  static const int initialCoins = 100;
  static const int initialHints = 3;

  final PreferencesBackend _preferences;
  final bool unlimitedCoins;
  final Map<String, LevelProgress> _progress = <String, LevelProgress>{};

  ThemeMode themeMode = ThemeMode.system;
  bool highContrast = false;
  bool tutorialCompleted = false;
  int coins = initialCoins;
  int hints = initialHints;

  static Future<LocalProgressStore> create() async {
    final store = LocalProgressStore._(
      SharedPreferencesBackend(),
      unlimitedCoins: debugUnlimitedCoinsEnabled,
    );
    await store._load();
    return store;
  }

  static Future<LocalProgressStore> createInMemory({
    Map<String, Object>? initialValues,
    bool unlimitedCoins = false,
  }) async {
    final store = LocalProgressStore._(
      MemoryPreferencesBackend(initialValues),
      unlimitedCoins: unlimitedCoins,
    );
    await store._load();
    return store;
  }

  int get completedLevelCount => completedCareerLevelCount;

  int get completedCareerLevelCount =>
      completedCareerLevelCountFor(SudokuVariant.classic9);

  int completedCareerLevelCountFor(SudokuVariant variant) => _progress.keys
      .where((key) => key.startsWith('${variant.persistenceKey}:'))
      .map(_puzzleIdFromStorageKey)
      .map(_careerLevelNumber)
      .whereType<int>()
      .toSet()
      .length;

  int get nextCareerLevelNumber =>
      nextCareerLevelNumberFor(SudokuVariant.classic9);

  int nextCareerLevelNumberFor(SudokuVariant variant) {
    var number = 1;
    while (_progress.containsKey(
      _storageKey(variant, _careerLevelId(number)),
    )) {
      number++;
    }
    return number;
  }

  int totalStarsFor(SudokuVariant variant) => _progress.entries
      .where((entry) => entry.key.startsWith('${variant.persistenceKey}:'))
      .fold<int>(0, (total, entry) => total + entry.value.stars);

  bool isCompleted(
    String puzzleId, {
    SudokuVariant variant = SudokuVariant.classic9,
  }) => _progress.containsKey(_storageKey(variant, puzzleId));

  bool isCareerLevelUnlocked(
    int number, {
    SudokuVariant variant = SudokuVariant.classic9,
  }) {
    if (number < 1) return false;
    return number == 1 ||
        _progress.containsKey(
          _storageKey(variant, _careerLevelId(number - 1)),
        );
  }

  LevelProgress? progressFor(
    String puzzleId, {
    SudokuVariant variant = SudokuVariant.classic9,
  }) => _progress[_storageKey(variant, puzzleId)];

  LevelProgress? progressForCareerLevel(
    int number, {
    SudokuVariant variant = SudokuVariant.classic9,
  }) {
    if (number < 1) return null;
    return _progress[_storageKey(variant, _careerLevelId(number))];
  }

  Future<void> recordResult({
    required String puzzleId,
    required int seconds,
    required int mistakes,
    required int hints,
    SudokuVariant variant = SudokuVariant.classic9,
  }) async {
    final stars = _calculateStars(mistakes: mistakes, hints: hints);
    final key = _storageKey(variant, puzzleId);
    final previous = _progress[key];
    _progress[key] = LevelProgress(
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
      bestHints: previous == null || hints < previous.bestHints
          ? hints
          : previous.bestHints,
      rewardClaimed: previous?.rewardClaimed ?? false,
    );
    await _saveProgress();
    notifyListeners();
  }

  Future<void> markCareerRewardClaimed({
    required int levelNumber,
    SudokuVariant variant = SudokuVariant.classic9,
  }) async {
    final key = _storageKey(variant, _careerLevelId(levelNumber));
    final previous = _progress[key];
    if (previous == null || previous.rewardClaimed) return;
    _progress[key] = LevelProgress(
      stars: previous.stars,
      bestSeconds: previous.bestSeconds,
      bestMistakes: previous.bestMistakes,
      bestHints: previous.bestHints,
      rewardClaimed: true,
    );
    await _saveProgress();
    notifyListeners();
  }

  Future<bool> spendCoins(int amount) async {
    if (amount <= 0 || coins < amount) return false;
    if (unlimitedCoins) return true;
    coins -= amount;
    await _preferences.setInt(_coinsKey, coins);
    notifyListeners();
    return true;
  }

  Future<void> addCoins(int amount) async {
    if (amount <= 0) return;
    if (unlimitedCoins) return;
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
    if (unlimitedCoins) {
      hints++;
      await _preferences.setInt(_hintsKey, hints);
      notifyListeners();
      return true;
    }
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
    await Future.wait<void>(<Future<void>>[
      _preferences.remove(_progressKey),
      _preferences.remove(_legacyProgressKey),
    ]);
    notifyListeners();
  }

  Future<void> clearProgressForVariant(SudokuVariant variant) async {
    _progress.removeWhere(
      (key, _) => key.startsWith('${variant.persistenceKey}:'),
    );
    await _saveProgress();
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
    if (unlimitedCoins) coins = debugUnlimitedCoinBalance;
    hints = await _preferences.getInt(_hintsKey) ?? initialHints;

    final raw = await _preferences.getString(_progressKey);
    if (raw != null && raw.isNotEmpty) {
      final normalized = _decodeProgress(raw, legacyVariant: null);
      if (normalized) await _saveProgress();
      return;
    }

    final legacyRaw = await _preferences.getString(_legacyProgressKey);
    if (legacyRaw == null || legacyRaw.isEmpty) return;
    _decodeProgress(legacyRaw, legacyVariant: SudokuVariant.classic9);
    if (_progress.isNotEmpty) {
      await _saveProgress();
    }
  }

  bool _decodeProgress(String raw, {required SudokuVariant? legacyVariant}) {
    var normalized = false;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final value = entry.value;
        final json = value is Map<String, dynamic>
            ? value
            : value is Map
            ? value.map((key, item) => MapEntry(key.toString(), item))
            : null;
        if (json == null) continue;
        final key = legacyVariant == null
            ? _normalizeStorageKey(entry.key)
            : _storageKey(legacyVariant, entry.key);
        normalized = normalized || key != entry.key || legacyVariant != null;
        final incoming = LevelProgress.fromJson(json);
        final previous = _progress[key];
        _progress[key] = previous == null
            ? incoming
            : _mergeProgress(previous, incoming);
      }
    } on FormatException {
      _progress.clear();
    }
    return normalized;
  }

  Future<void> _saveProgress() {
    final encoded = jsonEncode(
      _progress.map((key, value) => MapEntry(key, value.toJson())),
    );
    return _preferences.setString(_progressKey, encoded);
  }

  static String _storageKey(SudokuVariant variant, String puzzleId) {
    return '${variant.persistenceKey}:${_canonicalPuzzleId(puzzleId)}';
  }

  static String _normalizeStorageKey(String key) {
    final separator = key.indexOf(':');
    if (separator < 0) return key;
    final namespace = key.substring(0, separator);
    final puzzleId = key.substring(separator + 1);
    return '$namespace:${_canonicalPuzzleId(puzzleId)}';
  }

  static String _puzzleIdFromStorageKey(String key) {
    final separator = key.indexOf(':');
    final puzzleId = separator < 0 ? key : key.substring(separator + 1);
    return _canonicalPuzzleId(puzzleId);
  }

  static String _canonicalPuzzleId(String puzzleId) {
    final levelNumber = _careerLevelNumber(puzzleId);
    return levelNumber == null ? puzzleId : _careerLevelId(levelNumber);
  }

  static String _careerLevelId(int number) {
    return 'career-${number.toString().padLeft(3, '0')}';
  }

  static int? _careerLevelNumber(String id) {
    if (!id.startsWith('career-')) return null;
    return int.tryParse(id.substring('career-'.length));
  }

  static LevelProgress _mergeProgress(
    LevelProgress first,
    LevelProgress second,
  ) {
    return LevelProgress(
      stars: first.stars >= second.stars ? first.stars : second.stars,
      bestSeconds: _bestNonNegative(first.bestSeconds, second.bestSeconds),
      bestMistakes: _bestNonNegative(first.bestMistakes, second.bestMistakes),
      bestHints: _bestNonNegative(first.bestHints, second.bestHints),
      rewardClaimed: first.rewardClaimed || second.rewardClaimed,
    );
  }

  static int _bestNonNegative(int first, int second) {
    if (first < 0) return second;
    if (second < 0) return first;
    return first <= second ? first : second;
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
