import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../models/online_duel_emote_catalog.dart';
import '../../services/online_duel_emote_loadout_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/in_page_header.dart';

enum _EmoteFilter { all, reactions, taunts, status }

class EmoteLoadoutScreen extends StatefulWidget {
  const EmoteLoadoutScreen({super.key});

  @override
  State<EmoteLoadoutScreen> createState() => _EmoteLoadoutScreenState();
}

class _EmoteLoadoutScreenState extends State<EmoteLoadoutScreen> {
  final OnlineDuelEmoteLoadoutService _loadout =
      OnlineDuelEmoteLoadoutService.instance;

  _EmoteFilter _filter = _EmoteFilter.all;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _loadout.initialize();
    } catch (_) {
      _error = 'emote_selection_load_failed';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(OnlineDuelEmoteDefinition emote) async {
    final selected = _loadout.isSelected(emote.id);
    if (!selected && _loadout.isFull) {
      _showMessage(context.tr('quick_emotes_limit'));
      return;
    }
    if (selected && _loadout.selectedCount <= 1) {
      _showMessage(context.tr('keep_one_quick_emote'));
      return;
    }

    final changed = await _loadout.toggle(emote.id);
    if (!changed && mounted) {
      _showMessage(context.tr('emote_change_failed'));
    }
  }

  void _reorder(int oldIndex, int targetIndex) {
    final count = _loadout.selectedCount;
    if (oldIndex < 0 || oldIndex >= count || count <= 1) return;

    final int newIndex;
    if (targetIndex >= count) {
      newIndex = count;
    } else if (targetIndex > oldIndex) {
      newIndex = targetIndex + 1;
    } else {
      newIndex = targetIndex;
    }
    unawaited(_loadout.reorder(oldIndex, newIndex));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  List<OnlineDuelEmoteDefinition> get _visibleEmotes {
    switch (_filter) {
      case _EmoteFilter.all:
        return onlineDuelEmoteCatalog;
      case _EmoteFilter.reactions:
        return onlineDuelEmoteCatalog
            .where((e) => e.category == OnlineDuelEmoteCategory.reaction)
            .toList(growable: false);
      case _EmoteFilter.taunts:
        return onlineDuelEmoteCatalog
            .where((e) => e.category == OnlineDuelEmoteCategory.taunt)
            .toList(growable: false);
      case _EmoteFilter.status:
        return onlineDuelEmoteCatalog
            .where((e) => e.category == OnlineDuelEmoteCategory.status)
            .toList(growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: AnimatedBuilder(
                animation: _loadout,
                builder: (context, _) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                    children: [
                      InPageHeader(
                        title: context.tr('emotes'),
                        actions: [
                          IconButton(
                            tooltip: context.tr('restore_default_emotes'),
                            onPressed: _loading
                                ? null
                                : () async {
                                    final restoredMessage = context.tr(
                                      'default_emotes_restored',
                                    );
                                    await _loadout.resetToDefaults();
                                    if (mounted) {
                                      _showMessage(restoredMessage);
                                    }
                                  },
                            icon: const Icon(Icons.restart_alt_rounded),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        _InlineNotice(message: context.tr(_error!)),
                      ],
                      const SizedBox(height: 12),
                      _SectionTitle(
                        eyebrow: context.tr('your_loadout'),
                        title: context.tr('quick_emotes'),
                        subtitle: context.tr('quick_emotes_reorder_body'),
                        trailing:
                            '${_loadout.selectedCount}/${OnlineDuelEmoteLoadoutService.maxSlots}',
                      ),
                      const SizedBox(height: 11),
                      _QuickLoadoutGrid(
                        emotes: _loadout.selectedEmotes,
                        onMove: _reorder,
                      ),
                      const SizedBox(height: 22),
                      _SectionTitle(
                        eyebrow: context.tr('collection'),
                        title: context.tr('choose_reactions'),
                        subtitle: context.tr('choose_reactions_body'),
                      ),
                      const SizedBox(height: 10),
                      _FilterBar(
                        selected: _filter,
                        onSelected: (filter) =>
                            setState(() => _filter = filter),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final columns = width >= 680
                              ? 6
                              : width >= 520
                              ? 5
                              : width >= 360
                              ? 4
                              : 3;
                          final emotes = _visibleEmotes;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 9,
                                  crossAxisSpacing: 9,
                                  childAspectRatio: .90,
                                ),
                            itemCount: emotes.length,
                            itemBuilder: (context, index) {
                              final emote = emotes[index];
                              return _CollectionEmoteCard(
                                emote: emote,
                                selected: _loadout.isSelected(emote.id),
                                slot: _loadout.slotOf(emote.id),
                                onTap: () => unawaited(_toggle(emote)),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: TextStyle(
                  color: const Color(0xFF66C7FF).withValues(alpha: .86),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.25,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .52),
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF66C7FF).withValues(alpha: .10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF66C7FF).withValues(alpha: .18),
              ),
            ),
            child: Text(
              trailing!,
              style: const TextStyle(
                color: Color(0xFF8ED8FF),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickLoadoutGrid extends StatelessWidget {
  const _QuickLoadoutGrid({required this.emotes, required this.onMove});

  final List<OnlineDuelEmoteDefinition> emotes;
  final void Function(int oldIndex, int targetIndex) onMove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .065)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .14),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: OnlineDuelEmoteLoadoutService.maxSlots,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final emote = index < emotes.length ? emotes[index] : null;
              return _LoadoutDropSlot(
                index: index,
                emote: emote,
                onMove: onMove,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoadoutDropSlot extends StatelessWidget {
  const _LoadoutDropSlot({
    required this.index,
    required this.emote,
    required this.onMove,
  });

  final int index;
  final OnlineDuelEmoteDefinition? emote;
  final void Function(int oldIndex, int targetIndex) onMove;

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onMove(details.data, index),
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty;
        final card = _QuickSlotCard(
          index: index,
          emote: emote,
          highlighted: highlighted,
        );
        if (emote == null) return card;

        return LongPressDraggable<int>(
          data: index,
          maxSimultaneousDrags: 1,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox.square(
              dimension: 82,
              child: _QuickSlotCard(
                index: index,
                emote: emote,
                highlighted: true,
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: .24, child: card),
          child: card,
        );
      },
    );
  }
}

class _QuickSlotCard extends StatelessWidget {
  const _QuickSlotCard({
    required this.index,
    required this.emote,
    required this.highlighted,
  });

  final int index;
  final OnlineDuelEmoteDefinition? emote;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF66C7FF);
    final value = emote;
    return Semantics(
      label: value == null
          ? context.tr('empty_quick_emote_slot', <Object>[index + 1])
          : context.tr('quick_emote_slot_label', <Object>[
              context.tr(value.labelKey),
              index + 1,
            ]),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: highlighted
              ? accent.withValues(alpha: .15)
              : value == null
              ? Colors.white.withValues(alpha: .025)
              : const Color(0xFF152631).withValues(alpha: .92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted
                ? accent.withValues(alpha: .62)
                : value == null
                ? Colors.white.withValues(alpha: .055)
                : accent.withValues(alpha: .20),
            width: highlighted ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: value == null
                  ? Icon(
                      Icons.add_rounded,
                      size: 25,
                      color: Colors.white.withValues(alpha: .22),
                    )
                  : OnlineDuelEmoteVisual(
                      emote: value,
                      size: 50,
                      color: accent,
                    ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == null
                      ? Colors.white.withValues(alpha: .07)
                      : accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: value == null
                        ? Colors.white.withValues(alpha: .38)
                        : const Color(0xFF071015),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final _EmoteFilter selected;
  final ValueChanged<_EmoteFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChipButton(
            label: context.tr('all'),
            selected: selected == _EmoteFilter.all,
            onTap: () => onSelected(_EmoteFilter.all),
          ),
          const SizedBox(width: 7),
          _FilterChipButton(
            label: context.tr('reactions'),
            selected: selected == _EmoteFilter.reactions,
            onTap: () => onSelected(_EmoteFilter.reactions),
          ),
          const SizedBox(width: 7),
          _FilterChipButton(
            label: context.tr('taunts'),
            selected: selected == _EmoteFilter.taunts,
            onTap: () => onSelected(_EmoteFilter.taunts),
          ),
          const SizedBox(width: 7),
          _FilterChipButton(
            label: context.tr('status'),
            selected: selected == _EmoteFilter.status,
            onTap: () => onSelected(_EmoteFilter.status),
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF66C7FF);
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      label: Text(label),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white.withValues(alpha: .60),
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
      backgroundColor: Colors.black.withValues(alpha: .16),
      selectedColor: accent.withValues(alpha: .17),
      side: BorderSide(
        color: selected
            ? accent.withValues(alpha: .42)
            : Colors.white.withValues(alpha: .065),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

class _CollectionEmoteCard extends StatelessWidget {
  const _CollectionEmoteCard({
    required this.emote,
    required this.selected,
    required this.slot,
    required this.onTap,
  });

  final OnlineDuelEmoteDefinition emote;
  final bool selected;
  final int slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF66C7FF);
    return Semantics(
      button: true,
      selected: selected,
      label: selected
          ? context.tr('emote_equipped_slot', <Object>[
              context.tr(emote.labelKey),
              slot,
            ])
          : context.tr(emote.labelKey),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(7, 7, 7, 8),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: .095)
                  : Colors.black.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: .48)
                    : Colors.white.withValues(alpha: .055),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: OnlineDuelEmoteVisual(
                          emote: emote,
                          size: 58,
                          color: selected
                              ? accent
                              : Colors.white.withValues(alpha: .76),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.tr(emote.labelKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: selected ? .92 : .62,
                        ),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (selected)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$slot',
                        style: const TextStyle(
                          color: Color(0xFF071015),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
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

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC94D).withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFFC94D).withValues(alpha: .22),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFFFC94D),
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .72),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
