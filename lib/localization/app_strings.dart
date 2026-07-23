import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/sudoku.dart';

class AppStrings {
  AppStrings._(this._values);

  static const MethodChannel _channel = MethodChannel(
    'com.devovia.sudoku/localization',
  );

  static const String _catalogAsset =
      'assets/localization/Localizable.xcstrings';

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
    Locale('de'),
    Locale('fr'),
    Locale('es'),
    Locale('pt'),
    Locale('it'),
    Locale('nl'),
    Locale('pl'),
    Locale('ru'),
    Locale('uk'),
    Locale('ar'),
    Locale('hi'),
    Locale('id'),
    Locale('ja'),
    Locale('ko'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('th'),
    Locale('vi'),
    Locale('bn'),
    Locale('ur'),
  ];

  static const Map<String, String> english = <String, String>{
    'app_name': 'Sudoku Duel',
    'settings': 'Settings',
    'career': 'Career',
    'career_subtitle': 'Progress from beginner to expert',
    'local_duel': 'Local Duel',
    'local_duel_subtitle': 'Take 10-second turns on the same device',
    'daily_sudoku': 'Daily Sudoku',
    'daily_subtitle': 'One fresh puzzle every day',
    'how_to_play': 'How to play',
    'tutorial_repeat': 'Open the tutorial again',
    'tutorial_new': 'Learn in minutes with a 4×4 board',
    'welcome_returning_title': 'Ready for a Sudoku?',
    'welcome_new_title': "You don't need to know Sudoku.",
    'welcome_returning_body':
        'Continue your career or challenge someone beside you.',
    'welcome_new_body':
        'Learn the rules with a quick tutorial, then start your career.',
    'career_intro':
        'Start with the easiest puzzles and progress step by step.',
    'difficulty_beginner': 'Beginner',
    'difficulty_easy': 'Easy',
    'difficulty_medium': 'Medium',
    'difficulty_hard': 'Hard',
    'difficulty_expert': 'Expert',
    'complete_previous_level': 'Complete the previous level',
    'new_level': 'New level',
    'best_time': 'Best: %1$s',
    'level_title': '%1$s %2$d',
    'daily_puzzle_title': 'Daily Sudoku',
    'duel_puzzle_title': 'Local Duel',
    'mini_sudoku_title': 'Mini Sudoku',
    'congratulations': 'Congratulations!',
    'time': 'Time',
    'mistakes': 'Mistakes',
    'hints': 'Hints',
    'continue': 'Continue',
    'mistakes_count': 'Mistakes: %1$d',
    'hints_count': 'Hints: %1$d',
    'time_up_turn_passed':
        'Time is up. The turn passed to the other player.',
    'draw': 'Draw!',
    'player_won': 'Player %1$d won!',
    'turns_played': '%1$d turns played.',
    'main_menu': 'Main menu',
    'turn': 'Turn %1$d',
    'seconds': '%1$d seconds',
    'player_instruction': 'Player %1$d: Select a cell and make one move.',
    'player': 'Player %1$d',
    'today_puzzle_completed': "Today's puzzle is complete!",
    'tutorial_title': 'How to play Sudoku',
    'rule_rows_title': 'Complete each row',
    'rule_rows_description':
        'Each number can appear only once in every row.',
    'rule_columns_title': 'Check each column',
    'rule_columns_description':
        'The same number cannot appear twice in a column.',
    'rule_boxes_title': 'Remember the boxes',
    'rule_boxes_description':
        'Each bold box must also contain every number once.',
    'tutorial_ready': 'Ready? Try a 4×4 mini Sudoku.',
    'tutorial_completed': 'You understand Sudoku!',
    'start_mini_tutorial': 'Start mini tutorial',
    'appearance': 'Appearance',
    'system': 'System',
    'light': 'Light',
    'dark': 'Dark',
    'high_contrast': 'High contrast',
    'high_contrast_subtitle':
        'Makes the board and text easier to distinguish.',
    'data': 'Data',
    'clear_career_progress': 'Clear career progress',
    'completed_levels': '%1$d completed levels',
    'clear_progress_title': 'Clear progress?',
    'clear_progress_body':
        'Completed career levels and records will be removed.',
    'cancel': 'Cancel',
    'clear': 'Clear',
    'erase': 'Erase',
    'notes_on': 'Notes on',
    'notes': 'Notes',
    'undo': 'Undo',
    'hint': 'Hint',
    'board_label': '%1$d by %1$d Sudoku board',
    'cell_label': 'Row %1$d, column %2$d, %3$s',
    'empty': 'Empty',
  };

  final Map<String, String> _values;

  static Future<AppStrings> load() async {
    final values = Map<String, String>.from(english);
    await _loadStringCatalog(values);
    try {
      final response = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getStrings',
        <String, Object>{'keys': english.keys.toList(growable: false)},
      );
      if (response != null) {
        for (final entry in response.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key is String &&
              value is String &&
              value.isNotEmpty &&
              value != key) {
            values[key] = value;
          }
        }
      }
    } on MissingPluginException {
      // Unit tests and unsupported platforms use the catalog or English fallback.
    } on PlatformException {
      // A platform localization failure must never block app startup.
    }
    return AppStrings._(values);
  }

  static Future<void> _loadStringCatalog(Map<String, String> values) async {
    try {
      final source = await rootBundle.loadString(_catalogAsset);
      final catalog = jsonDecode(source) as Map<String, dynamic>;
      final catalogStrings = catalog['strings'];
      if (catalogStrings is! Map) return;

      final locale = PlatformDispatcher.instance.locale;
      final candidates = <String>[
        locale.toLanguageTag(),
        if (locale.scriptCode != null)
          '${locale.languageCode}-${locale.scriptCode}',
        locale.languageCode,
        'en',
      ];

      for (final entry in catalogStrings.entries) {
        final key = entry.key.toString();
        final definition = entry.value;
        if (definition is! Map) continue;
        final localizations = definition['localizations'];
        if (localizations is! Map) continue;
        for (final candidate in candidates) {
          final localization = localizations[candidate];
          if (localization is! Map) continue;
          final stringUnit = localization['stringUnit'];
          if (stringUnit is! Map) continue;
          final value = stringUnit['value'];
          if (value is String && value.isNotEmpty) {
            values[key] = value;
            break;
          }
        }
      }
    } on FlutterError {
      // The catalog is optional on platforms that use native resources.
    } on FormatException {
      // Keep the English fallback if a catalog is temporarily malformed.
    }
  }

  String text(String key, [List<Object> arguments = const <Object>[]]) {
    var value = _values[key] ?? english[key] ?? key;
    for (var index = 0; index < arguments.length; index++) {
      final position = index + 1;
      final replacement = arguments[index].toString();
      value = value
          .replaceAll('%$position\$s', replacement)
          .replaceAll('%$position\$d', replacement)
          .replaceAll('%${position}s', replacement)
          .replaceAll('%${position}d', replacement);
    }
    return value;
  }

  String difficultyLabel(SudokuDifficulty difficulty) => switch (difficulty) {
        SudokuDifficulty.beginner => text('difficulty_beginner'),
        SudokuDifficulty.easy => text('difficulty_easy'),
        SudokuDifficulty.medium => text('difficulty_medium'),
        SudokuDifficulty.hard => text('difficulty_hard'),
        SudokuDifficulty.expert => text('difficulty_expert'),
      };

  String puzzleTitle(SudokuPuzzle puzzle) {
    if (puzzle.id == 'tutorial-4x4') {
      return text('mini_sudoku_title');
    }
    if (puzzle.id.startsWith('daily-')) {
      return text('daily_puzzle_title');
    }
    if (puzzle.id.startsWith('duel-')) {
      return text('duel_puzzle_title');
    }
    final level = int.tryParse(puzzle.id.split('-').last);
    if (level != null) {
      return text(
        'level_title',
        <Object>[difficultyLabel(puzzle.difficulty), level],
      );
    }
    return puzzle.title;
  }
}

class AppStringsScope extends InheritedWidget {
  const AppStringsScope({
    super.key,
    required this.strings,
    required super.child,
  });

  final AppStrings strings;

  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    assert(scope != null, 'AppStringsScope is missing above this context.');
    return scope!.strings;
  }

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) =>
      oldWidget.strings != strings;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStringsScope.of(this);

  String tr(String key, [List<Object> arguments = const <Object>[]]) =>
      strings.text(key, arguments);
}
