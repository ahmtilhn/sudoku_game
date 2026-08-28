import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_messenger.dart';
import 'core/app_theme.dart';
import 'data/local_progress_store.dart';
import 'features/social/challenge_navigation_gate.dart';
import 'localization/app_strings.dart';

class SudokuApp extends StatefulWidget {
  const SudokuApp({super.key, required this.store, required this.strings});

  final LocalProgressStore store;
  final AppStrings strings;

  @override
  State<SudokuApp> createState() => _SudokuAppState();
}

class _SudokuAppState extends State<SudokuApp> with WidgetsBindingObserver {
  late AppStrings _strings;
  int _localeReloadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _strings = widget.strings;
    WidgetsBinding.instance.addObserver(this);

    // AppStrings is first loaded before runApp(). On iOS the native Flutter
    // bridge can still be registering at that moment, which would leave the
    // English fallback in memory for the entire session. Retry once after the
    // first frame, when the iOS bridge is guaranteed to be available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_reloadStringsForPlatformLocale());
    });
  }

  @override
  void didUpdateWidget(covariant SudokuApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.strings != widget.strings) {
      _strings = widget.strings;
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);
    unawaited(_reloadStringsForPlatformLocale());
  }

  Future<void> _reloadStringsForPlatformLocale() async {
    final generation = ++_localeReloadGeneration;
    final strings = await AppStrings.load();
    if (!mounted || generation != _localeReloadGeneration) return;
    setState(() {
      _strings = strings;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        return AppStringsScope(
          strings: _strings,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: AppMessenger.key,
            onGenerateTitle: (context) => context.tr('app_name'),
            theme: AppTheme.dark(highContrast: widget.store.highContrast),
            darkTheme: AppTheme.dark(highContrast: widget.store.highContrast),
            themeMode: ThemeMode.dark,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppStrings.supportedLocales,
            home: ChallengeNavigationGate(store: widget.store),
          ),
        );
      },
    );
  }
}
