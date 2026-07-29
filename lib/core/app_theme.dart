import 'package:flutter/material.dart';

@immutable
class GameColors extends ThemeExtension<GameColors> {
  const GameColors({
    required this.success,
    required this.onSuccess,
    required this.reward,
    required this.onReward,
    required this.localPlayer,
    required this.opponentPlayer,
    required this.warning,
    required this.timerCritical,
  });

  final Color success;
  final Color onSuccess;
  final Color reward;
  final Color onReward;
  final Color localPlayer;
  final Color opponentPlayer;
  final Color warning;
  final Color timerCritical;

  @override
  GameColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? reward,
    Color? onReward,
    Color? localPlayer,
    Color? opponentPlayer,
    Color? warning,
    Color? timerCritical,
  }) {
    return GameColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      reward: reward ?? this.reward,
      onReward: onReward ?? this.onReward,
      localPlayer: localPlayer ?? this.localPlayer,
      opponentPlayer: opponentPlayer ?? this.opponentPlayer,
      warning: warning ?? this.warning,
      timerCritical: timerCritical ?? this.timerCritical,
    );
  }

  @override
  GameColors lerp(ThemeExtension<GameColors>? other, double t) {
    if (other is! GameColors) return this;
    return GameColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      reward: Color.lerp(reward, other.reward, t)!,
      onReward: Color.lerp(onReward, other.onReward, t)!,
      localPlayer: Color.lerp(localPlayer, other.localPlayer, t)!,
      opponentPlayer: Color.lerp(opponentPlayer, other.opponentPlayer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      timerCritical: Color.lerp(timerCritical, other.timerCritical, t)!,
    );
  }
}

class AppTheme {
  const AppTheme._();

  static ThemeData light({required bool highContrast}) {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF1FB57E),
      onPrimary: Color(0xFF08110E),
      primaryContainer: Color(0xFFD7F8EB),
      onPrimaryContainer: Color(0xFF08110E),
      secondary: Color(0xFF3AA9FF),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFDCEEFF),
      onSecondaryContainer: Color(0xFF071B2E),
      tertiary: Color(0xFFD99C1D),
      onTertiary: Color(0xFF08110E),
      tertiaryContainer: Color(0xFFFFEDB3),
      onTertiaryContainer: Color(0xFF382500),
      error: Color(0xFFFF5B6B),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF172126),
      onSurfaceVariant: Color(0xFF59676D),
      outline: Color(0xFF7A898F),
      outlineVariant: Color(0xFFC6D0D4),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF2B3236),
      onInverseSurface: Color(0xFFEFF3F4),
      inversePrimary: Color(0xFF29D398),
      surfaceTint: Color(0xFF29D398),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF0F4F5),
      surfaceContainer: Color(0xFFE9EFF1),
      surfaceContainerHigh: Color(0xFFE1E8EA),
      surfaceContainerHighest: Color(0xFFD9E2E5),
    );
    return _build(
      scheme,
      highContrast: highContrast,
      gameColors: const GameColors(
        success: Color(0xFF1FB57E),
        onSuccess: Color(0xFF08110E),
        reward: Color(0xFFD99C1D),
        onReward: Color(0xFF08110E),
        localPlayer: Color(0xFF29D398),
        opponentPlayer: Color(0xFF3AA9FF),
        warning: Color(0xFFFF9F43),
        timerCritical: Color(0xFFFF5B6B),
      ),
    );
  }

  static ThemeData dark({required bool highContrast}) {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF29D398),
      onPrimary: Color(0xFF08110E),
      primaryContainer: Color(0xFF123429),
      onPrimaryContainer: Color(0xFFF8FAFC),
      secondary: Color(0xFF3AA9FF),
      onSecondary: Color(0xFF071B2E),
      secondaryContainer: Color(0xFF12304A),
      onSecondaryContainer: Color(0xFFF8FAFC),
      tertiary: Color(0xFFFFC94D),
      onTertiary: Color(0xFF2B1F00),
      tertiaryContainer: Color(0xFF4B390C),
      onTertiaryContainer: Color(0xFFF8FAFC),
      error: Color(0xFFFF5B6B),
      onError: Color(0xFF2F050B),
      errorContainer: Color(0xFF3A151D),
      onErrorContainer: Color(0xFFFFD7DC),
      surface: Color(0xFF0B1215),
      onSurface: Color(0xFFF8FAFC),
      onSurfaceVariant: Color(0xFFB7C3CA),
      outline: Color(0xFF7F8B94),
      outlineVariant: Color(0xFF2E414B),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFF8FAFC),
      onInverseSurface: Color(0xFF0B1215),
      inversePrimary: Color(0xFF1FB57E),
      surfaceTint: Color(0xFF29D398),
      surfaceContainerLowest: Color(0xFF0B1215),
      surfaceContainerLow: Color(0xFF121B20),
      surfaceContainer: Color(0xFF18242B),
      surfaceContainerHigh: Color(0xFF22313A),
      surfaceContainerHighest: Color(0xFF22313A),
    );
    return _build(
      scheme,
      highContrast: highContrast,
      gameColors: const GameColors(
        success: Color(0xFF29D398),
        onSuccess: Color(0xFF08110E),
        reward: Color(0xFFFFC94D),
        onReward: Color(0xFF2B1F00),
        localPlayer: Color(0xFF29D398),
        opponentPlayer: Color(0xFF7A5CFF),
        warning: Color(0xFFFF9F43),
        timerCritical: Color(0xFFFF5B6B),
      ),
    );
  }

  static ThemeData _build(
    ColorScheme scheme, {
    required bool highContrast,
    required GameColors gameColors,
  }) {
    final baseTextTheme = Typography.material2021().black;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.brightness == Brightness.light
          ? const Color(0xFFF4F6F8)
          : const Color(0xFF0B1215),
      extensions: <ThemeExtension<dynamic>>[gameColors],
      textTheme: baseTextTheme
          .copyWith(
            displayLarge: const TextStyle(
              fontSize: 28,
              height: 34 / 28,
              fontWeight: FontWeight.w700,
            ),
            headlineMedium: const TextStyle(
              fontSize: 22,
              height: 28 / 22,
              fontWeight: FontWeight.w700,
            ),
            titleLarge: const TextStyle(
              fontSize: 19,
              height: 25 / 19,
              fontWeight: FontWeight.w700,
            ),
            titleMedium: const TextStyle(
              fontSize: 17,
              height: 22 / 17,
              fontWeight: FontWeight.w700,
            ),
            bodyLarge: const TextStyle(fontSize: 16, height: 23 / 16),
            bodyMedium: const TextStyle(fontSize: 15, height: 22 / 15),
            bodySmall: const TextStyle(fontSize: 13, height: 18 / 13),
            labelLarge: const TextStyle(
              fontSize: 15,
              height: 20 / 15,
              fontWeight: FontWeight.w600,
            ),
            labelMedium: const TextStyle(
              fontSize: 13,
              height: 17 / 13,
              fontWeight: FontWeight.w600,
            ),
          )
          .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.brightness == Brightness.light
            ? const Color(0xFFF4F6F8)
            : const Color(0xFF0B1215),
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(52, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(52, 52),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: _SudokuPageTransitionsBuilder(),
          TargetPlatform.iOS: _SudokuPageTransitionsBuilder(),
          TargetPlatform.macOS: _SudokuPageTransitionsBuilder(),
          TargetPlatform.windows: _SudokuPageTransitionsBuilder(),
          TargetPlatform.linux: _SudokuPageTransitionsBuilder(),
        },
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.primary),
      ),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

class _SudokuPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SudokuPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) return child;
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.04, .018),
          end: Offset.zero,
        ).animate(curve),
        child: ScaleTransition(
          scale: Tween<double>(begin: .985, end: 1).animate(curve),
          child: child,
        ),
      ),
    );
  }
}
