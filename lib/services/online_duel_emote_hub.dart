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

  void receive(Object owner, String emoteId) {
    if (!identical(_owner, owner) ||
        !_matchActive ||
        _muted ||
        !onlineDuelEmoteCatalogIds.contains(emoteId)) {
      return;
    }
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
                const SizedBox(height: 6),
                _EmoteRoundButton(
                  hub: _hub,
                  dimension: 46,
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
            SizedBox(height: compact ? 3 : 6),
            _EmoteRoundButton(
              hub: hub,
              dimension: compact ? 42 : 46,
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
  final listenable = Listenable.merge(<Listenable>[hub, loadout]);

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: AnimatedBuilder(
        animation: listenable,
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, _) {
              final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
              final equipped = loadout.selectedEmotes.isEmpty
                  ? onlineDuelEmotesForIds(onlineDuelDefaultEmoteIds)
                  : loadout.selectedEmotes;
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Quick Emotes',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: hub.toggleMute,
                              icon: Icon(
                                hub.muted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                size: 18,
                              ),
                              label: Text(hub.muted ? 'Unmute' : 'Mute'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.05,
                          children: [
                            for (final emote in equipped)
                              _EmotePickerButton(
                                emote: emote,
                                enabled: hub.canSend,
                                onTap: () {
                                  if (hub.send(emote.id)) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                },
                              ),
                          ],
                        ),
                        if (hub.onCooldown) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Emotes have a short cooldown to prevent spam.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
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
    return Semantics(
      button: true,
      label: 'Open emotes',
      child: Material(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .96),
        elevation: 8,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: dimension,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  hub.muted
                      ? Icons.chat_bubble_outline_rounded
                      : Icons.add_reaction_outlined,
                  size: 23,
                ),
                if (hub.onCooldown)
                  Positioned.fill(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                if (hub.muted)
                  Positioned(
                    right: 7,
                    bottom: 7,
                    child: Icon(
                      Icons.volume_off_rounded,
                      size: 12,
                      color: Theme.of(context).colorScheme.error,
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
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: emote.label,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(
          alpha: enabled ? 1 : .5,
        ),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OnlineDuelEmoteVisual(
                emote: emote,
                size: 30,
                color: enabled ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 5),
              Text(
                emote.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 170),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: emote == null
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey<String>('duel-emote-${emote.id}-$accent'),
              margin: const EdgeInsets.only(bottom: 5),
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: .98),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: accent.withValues(alpha: .72)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .24),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: OnlineDuelEmoteVisual(
                emote: emote,
                size: 42,
                color: accent,
              ),
            ),
    );
  }
}
