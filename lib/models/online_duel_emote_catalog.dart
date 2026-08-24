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
  /// When a final PNG is wired later, [assetPath] takes priority.
  final String? shortText;

  /// Final transparent PNG asset path. Kept nullable so the whole selection
  /// and protocol system can be completed before the art pack lands.
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
      ),
      OnlineDuelEmoteDefinition(
        id: 'laugh',
        icon: Icons.sentiment_very_satisfied_rounded,
        label: 'Laugh',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'smug',
        icon: Icons.face_retouching_natural_rounded,
        label: 'Smug',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'bored',
        icon: Icons.bedtime_rounded,
        label: 'Bored',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'fire',
        icon: Icons.local_fire_department_rounded,
        label: 'Fire',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'crown',
        icon: Icons.workspace_premium_rounded,
        label: 'Crown',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'shocked',
        icon: Icons.sentiment_very_dissatisfied_rounded,
        label: 'Shocked',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'respect',
        icon: Icons.front_hand_rounded,
        label: 'Respect',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'angry',
        icon: Icons.mood_bad_rounded,
        label: 'Angry',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'clap',
        icon: Icons.back_hand_rounded,
        label: 'Slow Clap',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'facepalm',
        icon: Icons.face_6_rounded,
        label: 'Facepalm',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'eye_roll',
        icon: Icons.visibility_rounded,
        label: 'Eye Roll',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'shush',
        icon: Icons.volume_off_rounded,
        label: 'Shush',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'salty_cry',
        icon: Icons.water_drop_rounded,
        label: 'Salty Cry',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'love',
        icon: Icons.favorite_rounded,
        label: 'Love',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'plotting',
        icon: Icons.psychology_alt_rounded,
        label: 'Plotting',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'dizzy',
        icon: Icons.cyclone_rounded,
        label: 'Dizzy',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'victory',
        icon: Icons.emoji_events_rounded,
        label: 'Victory',
        category: OnlineDuelEmoteCategory.reaction,
      ),
      OnlineDuelEmoteDefinition(
        id: 'gg',
        icon: Icons.sports_esports_rounded,
        label: 'GG',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'GG',
      ),
      OnlineDuelEmoteDefinition(
        id: 'ez',
        icon: Icons.bolt_rounded,
        label: 'EZ',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'EZ',
      ),
      OnlineDuelEmoteDefinition(
        id: 'noob',
        icon: Icons.sports_esports_rounded,
        label: 'NOOB',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'NOOB',
      ),
      OnlineDuelEmoteDefinition(
        id: 'oops',
        icon: Icons.warning_amber_rounded,
        label: 'OOPS',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'OOPS',
      ),
      OnlineDuelEmoteDefinition(
        id: 'rekt',
        icon: Icons.flash_on_rounded,
        label: 'REKT',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'REKT',
      ),
      OnlineDuelEmoteDefinition(
        id: 'bruh',
        icon: Icons.question_mark_rounded,
        label: 'BRUH',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'BRUH',
      ),
      OnlineDuelEmoteDefinition(
        id: 'one_v_one',
        icon: Icons.swords_rounded,
        label: '1V1',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: '1V1',
      ),
      OnlineDuelEmoteDefinition(
        id: 'clutch',
        icon: Icons.emoji_events_rounded,
        label: 'CLUTCH',
        category: OnlineDuelEmoteCategory.taunt,
        shortText: 'CLUTCH',
      ),
      OnlineDuelEmoteDefinition(
        id: 'afk',
        icon: Icons.pause_circle_rounded,
        label: 'AFK',
        category: OnlineDuelEmoteCategory.status,
        shortText: 'AFK',
      ),
      OnlineDuelEmoteDefinition(
        id: 'lag',
        icon: Icons.wifi_off_rounded,
        label: 'LAG',
        category: OnlineDuelEmoteCategory.status,
        shortText: 'LAG',
      ),
    ];

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
              fontWeight: FontWeight.w1000,
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
