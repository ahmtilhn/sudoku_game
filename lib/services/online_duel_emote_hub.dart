import 'dart:async';

import 'package:flutter/material.dart';

import '../models/online_duel_emote_catalog.dart';
import 'online_duel_emote_loadout_service.dart';

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

/// Keeps the emote controls in the root overlay without manually owning an
/// OverlayEntry. OverlayPortal guarantees the overlay child cannot outlive the
/// duel widget that created it, which makes route teardown/forfeit safe.
class OnlineDuelEmoteDock extends StatefulWidget {
  const OnlineDuelEmoteDock({
    super.key,
    required this.child,
    this.compact = false,
  });

  final Widget child;
  final bool compact;

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

  void _onHubChanged() {
    _schedulePortalSync();
  }

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
    final bottomPadding = MediaQuery.viewPaddingOf(overlayContext).bottom;
    return Positioned(
      right: 12,
      bottom: bottomPadding + (widget.compact ? 118 : 138),
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
        return Column(
          key: const ValueKey<String>('online-duel-inline-emotes'),
          mainAxisSize: MainAxisSize.min,
          children: [
            OnlineDuelEmoteBubble(emoteId: hub.incomingEmoteId, accent: color),
            SizedBox(height: compact ? 2 : 4),
            _EmoteRoundButton(
              hub: hub,
              dimension: compact ? 48 : 50,
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
                        'QUICK EMOTES',
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
                            ? 'Unmute opponent emotes'
                            : 'Mute opponent emotes',
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
      label: 'Open emotes',
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
              border: Border.all(
                color: scheme.tertiary.withValues(alpha: .42),
              ),
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
      label: emote.label,
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
                border: Border.all(
                  color: Colors.white.withValues(alpha: .07),
                ),
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
        if (reduceMotion) return FadeTransition(opacity: animation, child: child);
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
