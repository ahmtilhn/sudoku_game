import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import 'duel_asset_icon.dart';

enum GameModalTone { info, success, warning, error, offline }

class GameModal {
  const GameModal._();

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    GameModalTone tone = GameModalTone.info,
    String? primaryLabel,
    String? secondaryLabel,
    bool dismissible = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: dismissible,
      builder: (dialogContext) => PopScope(
        canPop: dismissible,
        child: _GameModalDialog(
          title: title,
          message: message,
          tone: tone,
          primaryLabel: primaryLabel,
          secondaryLabel: secondaryLabel,
        ),
      ),
    );
    return result ?? false;
  }

  // Kept dynamic so the same modal can be awaited as a retry choice or used
  // as a fire-and-forget notice by existing screens without unsafe casts.
  static dynamic error(
    BuildContext context, {
    required String title,
    required String message,
    String? retryLabel,
    String? cancelLabel,
  }) => show(
    context,
    title: title,
    message: message,
    tone: GameModalTone.error,
    primaryLabel: retryLabel,
    secondaryLabel: cancelLabel,
  );

  static Future<bool> warning(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
  }) => show(
    context,
    title: title,
    message: message,
    tone: GameModalTone.warning,
    primaryLabel: confirmLabel,
    secondaryLabel: cancelLabel,
  );

  static Future<bool> success(
    BuildContext context, {
    required String title,
    required String message,
    String? actionLabel,
  }) => show(
    context,
    title: title,
    message: message,
    tone: GameModalTone.success,
    primaryLabel: actionLabel,
  );
}

class _GameModalDialog extends StatelessWidget {
  const _GameModalDialog({
    required this.title,
    required this.message,
    required this.tone,
    required this.primaryLabel,
    required this.secondaryLabel,
  });

  final String title;
  final String message;
  final GameModalTone tone;
  final String? primaryLabel;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final presentation = switch (tone) {
      GameModalTone.info => (
        asset: DuelAsset.statusWarningPro,
        accent: const Color(0xFF35D2FF),
      ),
      GameModalTone.success => (
        asset: DuelAsset.statusSuccessPro,
        accent: const Color(0xFF29D398),
      ),
      GameModalTone.warning => (
        asset: DuelAsset.statusWarningPro,
        accent: const Color(0xFFFFC73D),
      ),
      GameModalTone.error => (
        asset: DuelAsset.statusErrorPro,
        accent: const Color(0xFFFF525E),
      ),
      GameModalTone.offline => (
        asset: DuelAsset.statusOfflinePro,
        accent: const Color(0xFF8EA4BB),
      ),
    };

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: Semantics(
        container: true,
        liveRegion: true,
        namesRoute: true,
        label: '$title. $message',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0A1728),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: presentation.accent.withValues(alpha: .72),
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 34,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DuelAssetIcon(presentation.asset, size: 104),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .76),
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (primaryLabel != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: presentation.accent,
                          foregroundColor: const Color(0xFF07111E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(primaryLabel!),
                      ),
                    ),
                  if (secondaryLabel != null) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text(secondaryLabel!),
                      ),
                    ),
                  ],
                  if (primaryLabel == null && secondaryLabel == null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(context.tr('ok')),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
