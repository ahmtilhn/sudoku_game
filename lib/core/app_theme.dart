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
      primary: Color(0xFF176B63),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFD7F2EC),
      onPrimaryContainer: Color(0xFF08201D),
      secondary: Color(0xFF526575),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFD7E5EE),
      onSecondaryContainer: Color(0xFF10202B),
      tertiary: Color(0xFFA66F12),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFFFE2A7),
      onTertiaryContainer: Color(0xFF382500),
      error: Color(0xFFB83A3A),
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
      inversePrimary: Color(0xFF73D7C6),
      surfaceTint: Color(0xFF176B63),
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
        success: Color(0xFF287859),
        onSuccess: Color(0xFFFFFFFF),
        reward: Color(0xFFA66F12),
        onReward: Color(0xFFFFFFFF),
        localPlayer: Color(0xFF176B63),
        opponentPlayer: Color(0xFF3D74B6),
        warning: Color(0xFFA66F12),
        timerCritical: Color(0xFFB83A3A),
      ),
    );
  }

  static ThemeData dark({required bool highContrast}) {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF7BC6B2),
      onPrimary: Color(0xFF00372F),
      primaryContainer: Color(0xFF1D5A4F),
      onPrimaryContainer: Color(0xFFD9F3EB),
      secondary: Color(0xFFB8C6D8),
      onSecondary: Color(0xFF223040),
      secondaryContainer: Color(0xFF3B495D),
      onSecondaryContainer: Color(0xFFE0E8F2),
      tertiary: Color(0xFFE8C15A),
      onTertiary: Color(0xFF3C2B00),
      tertiaryContainer: Color(0xFF5C4614),
      onTertiaryContainer: Color(0xFFFFE6A7),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF172033),
      onSurface: Color(0xFFF3F6FA),
      onSurfaceVariant: Color(0xFFC5CFDD),
      outline: Color(0xFF8B98AA),
      outlineVariant: Color(0xFF46546A),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE7F0F2),
      onInverseSurface: Color(0xFF273135),
      inversePrimary: Color(0xFF176B63),
      surfaceTint: Color(0xFF73D7C6),
      surfaceContainerLowest: Color(0xFF101827),
      surfaceContainerLow: Color(0xFF1D273A),
      surfaceContainer: Color(0xFF243047),
      surfaceContainerHigh: Color(0xFF2C394F),
      surfaceContainerHighest: Color(0xFF35445B),
    );
    return _build(
      scheme,
      highContrast: highContrast,
      gameColors: const GameColors(
        success: Color(0xFF64D3A2),
        onSuccess: Color(0xFF003823),
        reward: Color(0xFFF1C45B),
        onReward: Color(0xFF3D2B00),
        localPlayer: Color(0xFF73D7C6),
        opponentPlayer: Color(0xFF8DB4E2),
        warning: Color(0xFFF1C45B),
        timerCritical: Color(0xFFFFB4AB),
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
          : const Color(0xFF121A2A),
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
            : const Color(0xFF121A2A),
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
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
