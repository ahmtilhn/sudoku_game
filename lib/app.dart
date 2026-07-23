import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_theme.dart';
import 'data/local_progress_store.dart';
import 'features/home/home_screen.dart';
import 'localization/app_strings.dart';

class SudokuApp extends StatelessWidget {
  const SudokuApp({
    super.key,
    required this.store,
    required this.strings,
  });

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
            onGenerateTitle: (context) => context.tr('app_name'),
            theme: AppTheme.light(highContrast: store.highContrast),
            darkTheme: AppTheme.dark(highContrast: store.highContrast),
            themeMode: store.themeMode,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppStrings.supportedLocales,
            localeResolutionCallback: (deviceLocale, supportedLocales) {
              if (deviceLocale == null) {
                return const Locale('en');
              }
              for (final locale in supportedLocales) {
                if (locale.languageCode == deviceLocale.languageCode &&
                    locale.scriptCode == deviceLocale.scriptCode) {
                  return locale;
                }
              }
              for (final locale in supportedLocales) {
                if (locale.languageCode == deviceLocale.languageCode) {
                  return locale;
                }
              }
              return const Locale('en');
            },
            home: HomeScreen(store: store),
          ),
        );
      },
    );
  }
}
