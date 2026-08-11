import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_messenger.dart';
import 'core/app_theme.dart';
import 'data/local_progress_store.dart';
import 'features/social/challenge_navigation_gate.dart';
import 'localization/app_strings.dart';

class SudokuApp extends StatelessWidget {
  const SudokuApp({super.key, required this.store, required this.strings});

  final LocalProgressStore store;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return AppStringsScope(
          strings: strings,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: AppMessenger.key,
            onGenerateTitle: (context) => context.tr('app_name'),
            theme: AppTheme.dark(highContrast: store.highContrast),
            darkTheme: AppTheme.dark(highContrast: store.highContrast),
            themeMode: ThemeMode.dark,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppStrings.supportedLocales,
            locale: const Locale('en'),
            home: ChallengeNavigationGate(store: store),
          ),
        );
      },
    );
  }
}
