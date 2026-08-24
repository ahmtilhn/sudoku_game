import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

@immutable
class OnlineDuelEmoteDefinition {
  const OnlineDuelEmoteDefinition({
    required this.id,
    required this.icon,
    required this.label,
  });

  final String id;
  final IconData icon;
  final String label;
}

const List<OnlineDuelEmoteDefinition> onlineDuelBasicEmotes =
    <OnlineDuelEmoteDefinition>[
      OnlineDuelEmoteDefinition(
        id: 'smile',
        icon: Icons.sentiment_satisfied_alt_rounded,
        label: 'Smile',
      ),
      OnlineDuelEmoteDefinition(
        id: 'laugh',
        icon: Icons.sentiment_very_satisfied_rounded,
        label: 'Laugh',
      ),
      OnlineDuelEmoteDefinition(
        id: 'smug',
        icon: Icons.face_retouching_natural_rounded,
        label: 'Smug',
      ),
      OnlineDuelEmoteDefinition(
        id: 'bored',
        icon: Icons.bedtime_rounded,
        label: 'Bored',
      ),
      OnlineDuelEmoteDefinition(
        id: 'fire',
        icon: Icons.local_fire_department_rounded,
        label: 'Fire',
      ),
      OnlineDuelEmoteDefinition(
        id: 'crown',
        icon: Icons.workspace_premium_rounded,
        label: 'Crown',
      ),
      OnlineDuelEmoteDefinition(
        id: 'shocked',
        icon: Icons.sentiment_very_dissatisfied_rounded,
        label: 'Shocked',
      ),
      OnlineDuelEmoteDefinition(
        id: 'respect',
        icon: Icons.front_hand_rounded,
        label: 'Respect',
      ),
    ];

const Set<String> onlineDuelBasicEmoteIds = <String>{
  'smile',
  'laugh',
  'smug',
  'bored',
  'fire',
  'crown',
  'shocked',
  'respect',
};

OnlineDuelEmoteDefinition? onlineDuelEmoteById(String? id) {
  if (id == null) return null;
  for (final emote in onlineDuelBasicEmotes) {
    if (emote.id == id) return emote;
  }
  return null;
}

typedef OnlineDuelEmoteSender = bool Function(String emoteId);

/// UI-facing, match-scoped bridge for lightweight online duel emotes.
///
/// The authoritative game state remains in [OnlineDuelController]. This hub is
/// intentionally ephemeral: it only owns presentation state, local mute state,
/// and client-side cooldown protection.
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
  String? _outgoingEmoteId;
  Timer? _cooldownTimer;
  Timer? _incomingTimer;
  Timer? _outgoingTimer;

  bool get attached => _owner != null && _sender != null;
  bool get matchActive => _matchActive;
  bool get visible => attached && _matchActive;
  bool get muted => _muted;
  bool get onCooldown => _cooldown;
  bool get canSend => visible && !_cooldown;
  String? get incomingEmoteId => _incomingEmoteId;
  String? get outgoingEmoteId => _outgoingEmoteId;

  Object attach({required OnlineDuelEmoteSender sender}) {
    _cancelTimers();
    final owner = Object();
    _owner = owner;
    _sender = sender;
    _matchActive = false;
    _muted = false;
    _cooldown = false;
    _incomingEmoteId = null;
    _outgoingEmoteId = null;
    notifyListeners();
    return owner;
  }

  void setMatchActive(Object owner, bool active) {
    if (!identical(_owner, owner) || _matchActive == active) return;
    _matchActive = active;
    if (!active) {
      _incomingTimer?.cancel();
      _outgoingTimer?.cancel();
      _incomingTimer = null;
      _outgoingTimer = null;
      _incomingEmoteId = null;
      _outgoingEmoteId = null;
    }
    notifyListeners();
  }

  bool send(String emoteId) {
    if (!canSend || !onlineDuelBasicEmoteIds.contains(emoteId)) return false;
    final sender = _sender;
    if (sender == null || !sender(emoteId)) return false;

    _cooldownTimer?.cancel();
    _outgoingTimer?.cancel();
    _cooldown = true;
    _outgoingEmoteId = emoteId;
    notifyListeners();

    _outgoingTimer = Timer(bubbleDuration, () {
      if (_outgoingEmoteId != emoteId) return;
      _outgoingEmoteId = null;
      notifyListeners();
    });
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
        !onlineDuelBasicEmoteIds.contains(emoteId)) {
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
    _outgoingEmoteId = null;
    notifyListeners();
  }

  void _cancelTimers() {
    _cooldownTimer?.cancel();
    _incomingTimer?.cancel();
    _outgoingTimer?.cancel();
    _cooldownTimer = null;
    _incomingTimer = null;
    _outgoingTimer = null;
  }
}

/// Installs the emote controls into the root overlay whenever an online duel is
/// active. Keeping the controls in the root overlay means they remain usable on
/// the opponent's turn even though the number pad itself is input-locked.
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
  OverlayEntry? _entry;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    _hub.addListener(_onHubChanged);
    _scheduleSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant OnlineDuelEmoteDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compact != widget.compact) {
      _entry?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _hub.removeListener(_onHubChanged);
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _onHubChanged() {
    _scheduleSync();
    _entry?.markNeedsBuild();
  }

  void _scheduleSync() {
    if (_syncScheduled || !mounted) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _syncOverlay();
    });
  }

  void _syncOverlay() {
    if (_hub.visible) {
      if (_entry != null) return;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;
      _entry = OverlayEntry(builder: _buildOverlay);
      overlay.insert(_entry!);
      return;
    }
    _entry?.remove();
    _entry = null;
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    if (!_hub.visible) return const SizedBox.shrink();
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
                _EmoteBubble(
                  emoteId: _hub.incomingEmoteId,
                  accent: Theme.of(context).colorScheme.tertiary,
                ),
                _EmoteBubble(
                  emoteId: _hub.outgoingEmoteId,
                  accent: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 6),
                Semantics(
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
                      onTap: () => _openPicker(context),
                      child: SizedBox.square(
                        dimension: 46,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              _hub.muted
                                  ? Icons.chat_bubble_outline_rounded
                                  : Icons.add_reaction_outlined,
                              size: 23,
                            ),
                            if (_hub.onCooldown)
                              Positioned.fill(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary,
                                  backgroundColor: Colors.transparent,
                                ),
                              ),
                            if (_hub.muted)
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
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: _hub,
          builder: (context, _) {
            return Padding(
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
                        onPressed: _hub.toggleMute,
                        icon: Icon(
                          _hub.muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          size: 18,
                        ),
                        label: Text(_hub.muted ? 'Unmute' : 'Mute'),
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
                      for (final emote in onlineDuelBasicEmotes)
                        _EmotePickerButton(
                          emote: emote,
                          enabled: _hub.canSend,
                          onTap: () {
                            if (_hub.send(emote.id)) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                        ),
                    ],
                  ),
                  if (_hub.onCooldown) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Emotes have a short cooldown to prevent spam.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
              Icon(
                emote.icon,
                size: 28,
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

class _EmoteBubble extends StatelessWidget {
  const _EmoteBubble({required this.emoteId, required this.accent});

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
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: .98),
                borderRadius: BorderRadius.circular(16),
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
              child: Icon(emote.icon, size: 30, color: accent),
            ),
    );
  }
}
