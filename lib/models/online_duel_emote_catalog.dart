import 'package:flutter/material.dart';

enum OnlineDuelEmoteCategory { reaction, taunt, status }

@immutable
class OnlineDuelEmoteDefinition {
  const OnlineDuelEmoteDefinition({
    required this.id,
    required this.icon,
    required this.label,
    required this.category,
    this.shortText,
    this.assetPath,
  });

  final String id;
  final IconData icon;
  final String label;
  final OnlineDuelEmoteCategory category;

  /// Optional text fallback for iconic text emotes such as GG / EZ.
  ///
  /// [assetPath] takes priority whenever final artwork is bundled.
  final String? shortText;

  /// Transparent PNG used by the collection, picker and incoming bubble.
  final String? assetPath;
}

const List<String> onlineDuelDefaultEmoteIds = <String>[
  'smile',
  'laugh',
  'smug',
  'bored',
  'fire',
  'crown',
  'shocked',
  'respect',
];

const List<OnlineDuelEmoteDefinition> onlineDuelEmoteCatalog =
    <OnlineDuelEmoteDefinition>[
      OnlineDuelEmoteDefinition(
        id: 'smile',
        icon: Icons.sentiment_satisfied_alt_rounded,
        label: 'Smile',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/smile.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'laugh',
        icon: Icons.sentiment_very_satisfied_rounded,
        label: 'Laugh',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/mock_laugh.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'smug',
        icon: Icons.face_retouching_natural_rounded,
        label: 'Smug',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/smug.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'bored',
        icon: Icons.bedtime_rounded,
        label: 'Bored',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/bored.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'fire',
        icon: Icons.local_fire_department_rounded,
        label: 'Fire',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/fire.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'crown',
        icon: Icons.workspace_premium_rounded,
        label: 'Crown',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/crown.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'shocked',
        icon: Icons.sentiment_very_dissatisfied_rounded,
        label: 'Shocked',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/shocked.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'respect',
        icon: Icons.front_hand_rounded,
        label: 'Respect',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/respect.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'angry',
        icon: Icons.mood_bad_rounded,
        label: 'Angry',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/angry.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'clap',
        icon: Icons.back_hand_rounded,
        label: 'Slow Clap',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/sarcastic_clap.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'facepalm',
        icon: Icons.face_6_rounded,
        label: 'Facepalm',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/facepalm.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'eye_roll',
        icon: Icons.visibility_rounded,
        label: 'Eye Roll',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/eye_roll.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'shush',
        icon: Icons.volume_off_rounded,
        label: 'Shush',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/shush.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'salty_cry',
        icon: Icons.water_drop_rounded,
        label: 'Salty Cry',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/salty_cry.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'love',
        icon: Icons.favorite_rounded,
        label: 'Love',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/mock_love.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'plotting',
        icon: Icons.psychology_alt_rounded,
        label: 'Plotting',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/plotting_thinking.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'dizzy',
        icon: Icons.cyclone_rounded,
        label: 'Dizzy',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/dizzy_ko.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'victory',
        icon: Icons.emoji_events_rounded,
        label: 'Victory',
        category: OnlineDuelEmoteCategory.reaction,
        assetPath: 'assets/emote/victory_peace.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'gg',
        icon: Icons.sports_esports_rounded,
        label: 'GG',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'GG',
        assetPath: 'assets/emote/gg_txt.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'ez',
        icon: Icons.bolt_rounded,
        label: 'EZ',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'EZ',
        assetPath: 'assets/emote/ez.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'noob',
        icon: Icons.sports_esports_rounded,
        label: 'NOOB',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'NOOB',
        assetPath: 'assets/emote/noob.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'oops',
        icon: Icons.warning_amber_rounded,
        label: 'OOPS',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'OOPS',
        assetPath: 'assets/emote/ooops.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'rekt',
        icon: Icons.flash_on_rounded,
        label: 'REKT',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'REKT',
        assetPath: 'assets/emote/rekt.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'bruh',
        icon: Icons.question_mark_rounded,
        label: 'BRUH',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'BRUH',
        assetPath: 'assets/emote/bruh.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'one_v_one',
        icon: Icons.compare_arrows_rounded,
        label: '1V1',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: '1V1',
        assetPath: 'assets/emote/1v1.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'clutch',
        icon: Icons.emoji_events_rounded,
        label: 'CLUTCH',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'CLUTCH',
        assetPath: 'assets/emote/clutch.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'afk',
        icon: Icons.pause_circle_rounded,
        label: 'AFK',
        category: OnlineDuelEmoteCategory.status,
        shortText: 'AFK',
        assetPath: 'assets/emote/afk.png',
      ),
      OnlineDuelEmoteDefinition(
        id: 'lag',
        icon: Icons.wifi_off_rounded,
        label: 'LAG',
        category: OnlineDuelEmoteCategory.status,
        shortText: 'LAG',
        assetPath: 'assets/emote/lag.png',
      ),
    ];

/// Compatibility aliases kept for older duel tests/call sites while the
/// selection UI migrates from the fixed starter set to the full catalog.
const List<OnlineDuelEmoteDefinition> onlineDuelBasicEmotes =
    onlineDuelEmoteCatalog;

const Set<String> onlineDuelEmoteCatalogIds = <String>{
  'smile',
  'laugh',
  'smug',
  'bored',
  'fire',
  'crown',
  'shocked',
  'respect',
  'angry',
  'clap',
  'facepalm',
  'eye_roll',
  'shush',
  'salty_cry',
  'love',
  'plotting',
  'dizzy',
  'victory',
  'gg',
  'ez',
  'noob',
  'oops',
  'rekt',
  'bruh',
  'one_v_one',
  'clutch',
  'afk',
  'lag',
};

const Set<String> onlineDuelBasicEmoteIds = onlineDuelEmoteCatalogIds;

OnlineDuelEmoteDefinition? onlineDuelEmoteById(String? id) {
  if (id == null) return null;
  for (final emote in onlineDuelEmoteCatalog) {
    if (emote.id == id) return emote;
  }
  return null;
}

List<OnlineDuelEmoteDefinition> onlineDuelEmotesForIds(
  Iterable<String> ids,
) {
  return <OnlineDuelEmoteDefinition>[
    for (final id in ids)
      if (onlineDuelEmoteById(id) case final emote?) emote,
  ];
}

class OnlineDuelEmoteVisual extends StatelessWidget {
  const OnlineDuelEmoteVisual({
    super.key,
    required this.emote,
    required this.size,
    this.color,
  });

  final OnlineDuelEmoteDefinition emote;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final assetPath = emote.assetPath;
    if (assetPath != null && assetPath.isNotEmpty) {
      return Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final text = emote.shortText;
    if (text != null && text.isNotEmpty) {
      return SizedBox.square(
        dimension: size,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              color: color ?? Theme.of(context).colorScheme.primary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -.8,
              height: 1,
            ),
          ),
        ),
      );
    }
    return Icon(
      emote.icon,
      size: size,
      color: color ?? Theme.of(context).colorScheme.primary,
    );
  }
}
