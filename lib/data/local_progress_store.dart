import 'dart:convert';

import 'package:flutter/material.dart';

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
  LocalProgressStore._(this._preferences) {
    _load();
  }

  static const _progressKey = 'career_progress_v1';
  static const _themeKey = 'theme_mode_v1';
  static const _highContrastKey = 'high_contrast_v1';
  static const _tutorialKey = 'tutorial_complete_v1';

  final SharedPreferences _preferences;
  final Map<String, LevelProgress> _progress = <String, LevelProgress>{};

  ThemeMode themeMode = ThemeMode.system;
  bool highContrast = false;
  bool tutorialCompleted = false;

  static Future<LocalProgressStore> create() async {
    final preferences = await SharedPreferences.getInstance();
    return LocalProgressStore._(preferences);
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

  void _load() {
    final themeIndex = _preferences.getInt(_themeKey);
    if (themeIndex != null &&
        themeIndex >= 0 &&
        themeIndex < ThemeMode.values.length) {
      themeMode = ThemeMode.values[themeIndex];
    }
    highContrast = _preferences.getBool(_highContrastKey) ?? false;
    tutorialCompleted = _preferences.getBool(_tutorialKey) ?? false;

    final raw = _preferences.getString(_progressKey);
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
