import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_messenger.dart';
import 'core/app_theme.dart';
import 'data/local_progress_store.dart';
import 'features/social/challenge_navigation_gate.dart';
import 'localization/app_strings.dart';
import 'services/reminder_notification_service.dart';

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

    // ReminderNotificationService.initialize() is started once from main after
    // the first frame and now performs the initial OS-permission sync itself.
    // Keep this callback focused on the iOS localization bridge retry so daily
    // reminder scheduling cannot race two startup initializations.
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ReminderNotificationService.instance.syncWithSystemPermission(),
      );
    }
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
    final darkTheme = AppTheme.dark();
    return AppStringsScope(
      strings: _strings,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: AppMessenger.key,
        onGenerateTitle: (context) => context.tr('app_name'),
        theme: darkTheme,
        darkTheme: darkTheme,
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
  }
}
