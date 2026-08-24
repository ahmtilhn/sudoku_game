import 'dart:async';

import 'package:flutter/material.dart';

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
      _error = 'Emote selection could not be loaded.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(OnlineDuelEmoteDefinition emote) async {
    final selected = _loadout.isSelected(emote.id);
    if (!selected && _loadout.isFull) {
      _showMessage('You can equip up to 8 quick emotes. Remove one first.');
      return;
    }
    if (selected && _loadout.selectedCount <= 1) {
      _showMessage('Keep at least one quick emote equipped.');
      return;
    }

    final changed = await _loadout.toggle(emote.id);
    if (!changed && mounted) {
      _showMessage('That emote could not be changed.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
                    children: [
                      InPageHeader(
                        title: 'Emotes',
                        actions: [
                          TextButton.icon(
                            onPressed: _loading
                                ? null
                                : () async {
                                    await _loadout.resetToDefaults();
                                    if (mounted) {
                                      _showMessage('Default emotes restored.');
                                    }
                                  },
                            icon: const Icon(Icons.restart_alt_rounded, size: 19),
                            label: const Text('Reset'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _LoadoutSummaryCard(
                        selectedCount: _loadout.selectedCount,
                        loading: _loading,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        _InlineNotice(message: _error!),
                      ],
                      const SizedBox(height: 14),
                      _SectionTitle(
                        title: 'Quick Emotes',
                        subtitle:
                            'These are the emotes shown during online duels. Drag to change their order.',
                        trailing: '${_loadout.selectedCount}/8',
                      ),
                      const SizedBox(height: 9),
                      _SelectedEmoteRail(
                        emotes: _loadout.selectedEmotes,
                        onReorder: (oldIndex, newIndex) => unawaited(
                          _loadout.reorder(oldIndex, newIndex),
                        ),
                        onRemove: (emote) => unawaited(_toggle(emote)),
                      ),
                      const SizedBox(height: 18),
                      const _SectionTitle(
                        title: 'Emote Collection',
                        subtitle:
                            'Tap an emote to equip or remove it from your 8 quick slots.',
                      ),
                      const SizedBox(height: 9),
                      _FilterBar(
                        selected: _filter,
                        onSelected: (filter) => setState(() => _filter = filter),
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
                                  childAspectRatio: .88,
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

class _LoadoutSummaryCard extends StatelessWidget {
  const _LoadoutSummaryCard({
    required this.selectedCount,
    required this.loading,
  });

  final int selectedCount;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF66C7FF);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: accent.withValues(alpha: .18)),
            ),
            alignment: Alignment.center,
            child: loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.add_reaction_rounded,
                    color: accent,
                    size: 27,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Duel Emote Loadout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Pick the reactions and taunts you want available in Ready, live matches and result screens.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .58),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$selectedCount/8',
              style: const TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .50),
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Text(
            trailing!,
            style: const TextStyle(
              color: Color(0xFF66C7FF),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ],
    );
  }
}

class _SelectedEmoteRail extends StatelessWidget {
  const _SelectedEmoteRail({
    required this.emotes,
    required this.onReorder,
    required this.onRemove,
  });

  final List<OnlineDuelEmoteDefinition> emotes;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<OnlineDuelEmoteDefinition> onRemove;

  @override
  Widget build(BuildContext context) {
    if (emotes.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 108,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: emotes.length,
        onReorder: onReorder,
        proxyDecorator: (child, index, animation) => Material(
          color: Colors.transparent,
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
        itemBuilder: (context, index) {
          final emote = emotes[index];
          return ReorderableDragStartListener(
            key: ValueKey<String>('equipped-${emote.id}'),
            index: index,
            child: Container(
              width: 88,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 5),
              decoration: BoxDecoration(
                color: const Color(0xFF66C7FF).withValues(alpha: .09),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF66C7FF).withValues(alpha: .26),
                ),
              ),
              child: Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OnlineDuelEmoteVisual(
                        emote: emote,
                        size: 42,
                        color: const Color(0xFF66C7FF),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        emote.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .78),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      width: 19,
                      height: 19,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFF66C7FF),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Color(0xFF071015),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -5,
                    top: -5,
                    child: IconButton(
                      tooltip: 'Remove ${emote.label}',
                      onPressed: () => onRemove(emote),
                      visualDensity: VisualDensity.compact,
                      iconSize: 15,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        _FilterChipButton(
          label: 'All',
          selected: selected == _EmoteFilter.all,
          onTap: () => onSelected(_EmoteFilter.all),
        ),
        _FilterChipButton(
          label: 'Reactions',
          selected: selected == _EmoteFilter.reactions,
          onTap: () => onSelected(_EmoteFilter.reactions),
        ),
        _FilterChipButton(
          label: 'Taunts',
          selected: selected == _EmoteFilter.taunts,
          onTap: () => onSelected(_EmoteFilter.taunts),
        ),
        _FilterChipButton(
          label: 'Status',
          selected: selected == _EmoteFilter.status,
          onTap: () => onSelected(_EmoteFilter.status),
        ),
      ],
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
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white.withValues(alpha: .60),
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
      backgroundColor: Colors.black.withValues(alpha: .16),
      selectedColor: accent.withValues(alpha: .18),
      side: BorderSide(
        color: selected
            ? accent.withValues(alpha: .42)
            : Colors.white.withValues(alpha: .06),
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
      label: '${emote.label}${selected ? ', equipped in slot $slot' : ''}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: .10)
                  : Colors.black.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(16),
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
                          size: 46,
                          color: selected
                              ? accent
                              : Colors.white.withValues(alpha: .72),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      emote.label,
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
                Positioned(
                  right: 0,
                  top: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 140),
                    child: selected
                        ? Container(
                            key: ValueKey<int>(slot),
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
                          )
                        : Icon(
                            Icons.add_circle_outline_rounded,
                            key: const ValueKey<String>('add'),
                            size: 21,
                            color: Colors.white.withValues(alpha: .34),
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
