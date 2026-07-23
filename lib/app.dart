import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'data/local_progress_store.dart';
import 'features/home/home_screen.dart';

class SudokuApp extends StatelessWidget {
  const SudokuApp({super.key, required this.store});

  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Sudoku Duel',
          theme: AppTheme.light(highContrast: store.highContrast),
          darkTheme: AppTheme.dark(highContrast: store.highContrast),
          themeMode: store.themeMode,
          home: HomeScreen(store: store),
        );
      },
    );
  }
}
