import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../models/online_duel_emote_catalog.dart';
import 'online_duel_emote_loadout_service.dart';
import 'sound_effects_service.dart';

export '../models/online_duel_emote_catalog.dart';

typedef OnlineDuelEmoteSender = bool Function(String emoteId);

/// Match-scoped presentation bridge for lightweight online duel emotes.
///
/// Emotes never become authoritative duel state. This class only owns local
/// cooldown, local mute and the short-lived incoming opponent presentation.
class OnlineDuelEmoteHub extends ChangeNotifier {
  OnlineDuelEmoteHub();

  static final OnlineDuelEmoteHub instance = OnlineDuelEmoteHub();

  static const Duration cooldownDuration = Duration(seconds: 3);
  static const Duration bubbleDuration = Duration(milliseconds: 1900);

  Object? _owner;
  OnlineDuelEmoteSender? _sender;
  bool _matchActive = false;
  bool _muted = false;
  bool _cooldown = false;
  String? _incomingEmoteId;
  Timer? _cooldownTimer;
  Timer? _incomingTimer;

  bool get attached => _owner != null && _sender != null;
  bool get matchActive => _matchActive;
  bool get visible => attached && _matchActive;
  bool get muted => _muted;
  bool get onCooldown => _cooldown;
  bool get canSend => visible && !_cooldown;
  String? get incomingEmoteId => _incomingEmoteId;

  Object attach({required OnlineDuelEmoteSender sender}) {
    _cancelTimers();
    final owner = Object();
    _owner = owner;
    _sender = sender;
    _matchActive = false;
    _muted = false;
    _cooldown = false;
    _incomingEmoteId = null;
    notifyListeners();
    return owner;
  }

  void setMatchActive(Object owner, bool active) {
    if (!identical(_owner, owner) || _matchActive == active) return;
    _matchActive = active;
    if (!active) {
      _incomingTimer?.cancel();
      _incomingTimer = null;
      _incomingEmoteId = null;
    }
    notifyListeners();
  }

  bool send(String emoteId) {
    if (!canSend || !onlineDuelEmoteCatalogIds.contains(emoteId)) return false;
    final sender = _sender;
    if (sender == null || !sender(emoteId)) return false;

    unawaited(SoundEffectsService.instance.play(SoundEffect.emoteSend));
    _cooldownTimer?.cancel();
    _cooldown = true;
    notifyListeners();
    _cooldownTimer = Timer(cooldownDuration, () {
      _cooldown = false;
      notifyListeners();
    });
    return true;
  }

  void receive(Object owner, String emoteId, {bool forceActive = false}) {
    if (!identical(_owner, owner) ||
        (!forceActive && !_matchActive) ||
        _muted ||
        !onlineDuelEmoteCatalogIds.contains(emoteId)) {
      return;
    }
    _present(owner: owner, emoteId: emoteId, forceActive: forceActive);
  }

  void _present({
    required Object? owner,
    required String emoteId,
    required bool forceActive,
  }) {
    if (!identical(_owner, owner)) return;
    if (forceActive) _matchActive = true;
    _incomingTimer?.cancel();
    _incomingEmoteId = emoteId;
    unawaited(SoundEffectsService.instance.play(SoundEffect.emoteReceive));
    notifyListeners();
    _incomingTimer = Timer(bubbleDuration, () {
      if (_incomingEmoteId != emoteId) return;
      _incomingEmoteId = null;
      notifyListeners();
    });
  }

  void serverRejected(Object owner, String reason) {
    if (!identical(_owner, owner)) return;
    if (reason == 'emote_cooldown' && !_cooldown) {
      _cooldown = true;
      notifyListeners();
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(cooldownDuration, () {
        _cooldown = false;
        notifyListeners();
      });
    }
  }

  void toggleMute() {
    if (!attached) return;
    _muted = !_muted;
    if (_muted) {
      _incomingTimer?.cancel();
      _incomingTimer = null;
      _incomingEmoteId = null;
    }
    notifyListeners();
  }

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _cancelTimers();
    _owner = null;
    _sender = null;
    _matchActive = false;
    _muted = false;
    _cooldown = false;
    _incomingEmoteId = null;
    notifyListeners();
  }

  void _cancelTimers() {
    _cooldownTimer?.cancel();
    _incomingTimer?.cancel();
    _cooldownTimer = null;
    _incomingTimer = null;
  }
}

class OnlineDuelEmoteDock extends StatefulWidget {
  const OnlineDuelEmoteDock({
    super.key,
    required this.child,
    this.compact = false,
    this.interactionEnabled,
  });

  final Widget child;
  final bool compact;
  final bool? interactionEnabled;

  @override
  State<OnlineDuelEmoteDock> createState() => _OnlineDuelEmoteDockState();
}

class _OnlineDuelEmoteDockState extends State<OnlineDuelEmoteDock> {
  final OnlineDuelEmoteHub _hub = OnlineDuelEmoteHub.instance;
  final OverlayPortalController _portalController = OverlayPortalController();
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    _hub.addListener(_onHubChanged);
    _schedulePortalSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePortalSync();
  }

  @override
  void dispose() {
    _hub.removeListener(_onHubChanged);
    super.dispose();
  }

  void _onHubChanged() => _schedulePortalSync();

  void _schedulePortalSync() {
    if (_syncScheduled || !mounted) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      if (_hub.visible) {
        _portalController.show();
      } else {
        _portalController.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portalController,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: _buildOverlay,
      child: widget.child,
    );
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final viewPadding = MediaQuery.viewPaddingOf(overlayContext);
    if (widget.compact) {
      final localTurn = widget.interactionEnabled ?? true;
      return Stack(
        children: [
          Positioned(
            top: viewPadding.top + 75,
            left: 52,
            right: 52,
            child: IgnorePointer(
              child: Material(
                type: MaterialType.transparency,
                child: _PersistentDuelTurnStrip(localTurn: localTurn),
              ),
            ),
          ),
          Positioned(
            top: viewPadding.top + 121,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Material(
                type: MaterialType.transparency,
                child: AnimatedBuilder(
                  animation: _hub,
                  builder: (context, _) {
                    if (!_hub.visible || _hub.incomingEmoteId == null) {
                      return const SizedBox.shrink();
                    }
                    return Center(
                      child: _OpponentEmotePresentation(
                        emoteId: _hub.incomingEmoteId,
                        accent: Theme.of(context).colorScheme.tertiary,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: viewPadding.bottom + 122,
            child: Material(
              type: MaterialType.transparency,
              child: AnimatedBuilder(
                animation: _hub,
                builder: (context, _) {
                  if (!_hub.visible) return const SizedBox.shrink();
                  return _CompactDuelControlBar(
                    hub: _hub,
                    onEmotes: () => _openPicker(context),
                    onOptions: () => _openMatchOptions(context),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    return Positioned(
      right: 12,
      bottom: viewPadding.bottom + 138,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _hub,
          builder: (context, _) {
            if (!_hub.visible) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                OnlineDuelEmoteBubble(
                  emoteId: _hub.incomingEmoteId,
                  accent: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(height: 4),
                _EmoteRoundButton(
                  hub: _hub,
                  dimension: 50,
                  onTap: () => _openPicker(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    await showOnlineDuelEmotePicker(context, _hub);
  }

  Future<void> _openMatchOptions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .42),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Material(
            color: const Color(0xFF101D27),
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('match_options'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _hub.muted
                            ? context.tr('unmute')
                            : context.tr('mute'),
                        onPressed: _hub.toggleMute,
                        icon: Icon(
                          _hub.muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ListTile(
                    leading: const Icon(
                      Icons.flag_rounded,
                      color: Color(0xFFFF8C88),
                    ),
                    title: Text(
                      context.tr('forfeit_match'),
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(context.tr('confirmation_required')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(sheetContext).pop('forfeit'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (action != 'forfeit' || !context.mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;
    await Navigator.of(context).maybePop();
  }
}

class _PersistentDuelTurnStrip extends StatelessWidget {
  const _PersistentDuelTurnStrip({required this.localTurn});

  final bool localTurn;

  @override
  Widget build(BuildContext context) {
    final accent = localTurn
        ? const Color(0xFF29D398)
        : const Color(0xFFFFC94D);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1722).withValues(alpha: .96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: .50)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .16), blurRadius: 14),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            localTurn ? Icons.touch_app_rounded : Icons.hourglass_top_rounded,
            color: accent,
            size: 18,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              localTurn
                  ? context.tr('your_turn_make_move_compact')
                  : context.tr('opponent_turn_waiting_compact'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: .25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactDuelControlBar extends StatelessWidget {
  const _CompactDuelControlBar({
    required this.hub,
    required this.onEmotes,
    required this.onOptions,
  });

  final OnlineDuelEmoteHub hub;
  final VoidCallback onEmotes;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111D29).withValues(alpha: .985),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .32),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF29D398),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('duel_controls'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .55),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .9,
              ),
            ),
          ),
          _CompactRoundControl(
            tooltip: context.tr('emotes'),
            onTap: onEmotes,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.add_reaction_outlined,
                  color: hub.onCooldown
                      ? Colors.white38
                      : const Color(0xFFFFD66B),
                  size: 23,
                ),
                if (hub.onCooldown)
                  const SizedBox.square(
                    dimension: 34,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CompactRoundControl(
            tooltip: context.tr('match_options'),
            onTap: onOptions,
            child: const Icon(
              Icons.more_horiz_rounded,
              color: Color(0xFFFFD66B),
              size: 25,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactRoundControl extends StatelessWidget {
  const _CompactRoundControl({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF1A2A37),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(dimension: 39, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _OpponentEmotePresentation extends StatelessWidget {
  const _OpponentEmotePresentation({
    required this.emoteId,
    required this.accent,
  });

  final String? emoteId;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 10, 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1722).withValues(alpha: .96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: .30)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .30), blurRadius: 16),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OnlineDuelEmoteBubble(emoteId: emoteId, accent: accent),
          const SizedBox(width: 2),
          Text(
            context.tr('opponent'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: .68),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .9,
            ),
          ),
        ],
      ),
    );
  }
}

class OnlineDuelInlineEmoteSurface extends StatelessWidget {
  const OnlineDuelInlineEmoteSurface({
    super.key,
    this.compact = false,
    this.accent,
  });

  final bool compact;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final hub = OnlineDuelEmoteHub.instance;
    return AnimatedBuilder(
      animation: hub,
      builder: (context, _) {
        if (!hub.visible) return const SizedBox.shrink();
        final color = accent ?? Theme.of(context).colorScheme.tertiary;
        if (compact) {
          const dimension = 48.0;
          const bubbleScale = .70;
          return SizedBox.square(
            key: const ValueKey<String>('online-duel-inline-emotes'),
            dimension: dimension,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PositionedDirectional(
                  start: dimension + 6,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Transform.scale(
                      scale: bubbleScale,
                      alignment: AlignmentDirectional.bottomStart,
                      child: OnlineDuelEmoteBubble(
                        emoteId: hub.incomingEmoteId,
                        accent: color,
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 0,
                  bottom: 0,
                  child: _EmoteRoundButton(
                    hub: hub,
                    dimension: dimension,
                    onTap: () => showOnlineDuelEmotePicker(context, hub),
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          key: const ValueKey<String>('online-duel-inline-emotes'),
          mainAxisSize: MainAxisSize.min,
          children: [
            OnlineDuelEmoteBubble(emoteId: hub.incomingEmoteId, accent: color),
            const SizedBox(height: 4),
            _EmoteRoundButton(
              hub: hub,
              dimension: 50,
              onTap: () => showOnlineDuelEmotePicker(context, hub),
            ),
          ],
        );
      },
    );
  }
}

Future<void> showOnlineDuelEmotePicker(
  BuildContext context,
  OnlineDuelEmoteHub hub,
) {
  final loadout = OnlineDuelEmoteLoadoutService.instance;
  unawaited(loadout.initialize());
  final wide = MediaQuery.sizeOf(context).width >= 760;

  if (wide) {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: .18),
      builder: (dialogContext) => SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 92),
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 370),
                child: _QuickEmotePickerPanel(
                  hub: hub,
                  loadout: loadout,
                  onSent: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .32),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: _QuickEmotePickerPanel(
          hub: hub,
          loadout: loadout,
          onSent: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    ),
  );
}

class _QuickEmotePickerPanel extends StatelessWidget {
  const _QuickEmotePickerPanel({
    required this.hub,
    required this.loadout,
    required this.onSent,
  });

  final OnlineDuelEmoteHub hub;
  final OnlineDuelEmoteLoadoutService loadout;
  final VoidCallback onSent;

  @override
  Widget build(BuildContext context) {
    final listenable = Listenable.merge(<Listenable>[hub, loadout]);
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final equipped = loadout.selectedEmotes.isEmpty
            ? onlineDuelEmotesForIds(onlineDuelDefaultEmoteIds)
            : loadout.selectedEmotes;
        return Material(
          elevation: 18,
          color: const Color(0xFF121D24).withValues(alpha: .99),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: .085)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .30),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        context.tr('quick_emotes'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .66),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.15,
                        ),
                      ),
                      const Spacer(),
                      Semantics(
                        button: true,
                        label: hub.muted
                            ? context.tr('unmute_opponent_emotes')
                            : context.tr('mute_opponent_emotes'),
                        child: IconButton(
                          tooltip: hub.muted ? 'Unmute' : 'Mute',
                          visualDensity: VisualDensity.compact,
                          onPressed: hub.toggleMute,
                          icon: Icon(
                            hub.muted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            color: hub.muted
                                ? scheme.error
                                : Colors.white.withValues(alpha: .72),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: equipped.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                    itemBuilder: (context, index) {
                      final emote = equipped[index];
                      return _EmotePickerButton(
                        emote: emote,
                        enabled: hub.canSend,
                        onTap: () {
                          if (hub.send(emote.id)) onSent();
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmoteRoundButton extends StatelessWidget {
  const _EmoteRoundButton({
    required this.hub,
    required this.dimension,
    required this.onTap,
  });

  final OnlineDuelEmoteHub hub;
  final double dimension;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: context.tr('open_emotes'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Ink(
            width: dimension,
            height: dimension,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF263947), Color(0xFF17252E)],
              ),
              border: Border.all(color: scheme.tertiary.withValues(alpha: .42)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .32),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
                BoxShadow(
                  color: scheme.tertiary.withValues(alpha: .09),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.add_reaction_outlined,
                  size: 24,
                  color: hub.onCooldown
                      ? Colors.white.withValues(alpha: .46)
                      : const Color(0xFFFFD66B),
                ),
                if (hub.onCooldown)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: scheme.primary,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ),
                if (hub.muted)
                  Positioned(
                    right: 5,
                    bottom: 5,
                    child: Container(
                      width: 17,
                      height: 17,
                      decoration: BoxDecoration(
                        color: const Color(0xFF18242B),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .12),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.volume_off_rounded,
                        size: 10,
                        color: scheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmotePickerButton extends StatelessWidget {
  const _EmotePickerButton({
    required this.emote,
    required this.enabled,
    required this.onTap,
  });

  final OnlineDuelEmoteDefinition emote;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: context.tr(emote.labelKey),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled ? 1 : .42,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onTap : null,
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .045),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: .07)),
              ),
              child: Center(
                child: OnlineDuelEmoteVisual(
                  emote: emote,
                  size: 50,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnlineDuelEmoteBubble extends StatelessWidget {
  const OnlineDuelEmoteBubble({
    super.key,
    required this.emoteId,
    required this.accent,
  });

  final String? emoteId;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final emote = onlineDuelEmoteById(emoteId);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 170),
      transitionBuilder: (child, animation) {
        if (reduceMotion) {
          return FadeTransition(opacity: animation, child: child);
        }
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .86, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      child: emote == null
          ? const SizedBox.shrink()
          : SizedBox(
              key: ValueKey<String>('duel-emote-${emote.id}-$accent'),
              width: 76,
              height: 76,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .24),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: accent.withValues(alpha: .10),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Center(
                  child: OnlineDuelEmoteVisual(
                    emote: emote,
                    size: 70,
                    color: accent,
                  ),
                ),
              ),
            ),
    );
  }
}
