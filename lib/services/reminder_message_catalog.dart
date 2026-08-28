import 'dart:math';

import '../localization/app_strings.dart';

class ReminderMessageCatalog {
  const ReminderMessageCatalog._();

  static const List<String> _openerKeys = <String>[
    'reminder_opener_01',
    'reminder_opener_02',
    'reminder_opener_03',
    'reminder_opener_04',
    'reminder_opener_05',
    'reminder_opener_06',
    'reminder_opener_07',
    'reminder_opener_08',
    'reminder_opener_09',
    'reminder_opener_10',
    'reminder_opener_11',
    'reminder_opener_12',
  ];
  static const List<String> _challengeKeys = <String>[
    'reminder_challenge_01',
    'reminder_challenge_02',
    'reminder_challenge_03',
    'reminder_challenge_04',
    'reminder_challenge_05',
    'reminder_challenge_06',
    'reminder_challenge_07',
    'reminder_challenge_08',
    'reminder_challenge_09',
    'reminder_challenge_10',
    'reminder_challenge_11',
    'reminder_challenge_12',
  ];
  static const List<String> _closerKeys = <String>[
    'reminder_closer_01',
    'reminder_closer_02',
    'reminder_closer_03',
    'reminder_closer_04',
    'reminder_closer_05',
    'reminder_closer_06',
    'reminder_closer_07',
    'reminder_closer_08',
  ];

  static int get uniqueMessageCount =>
      _openerKeys.length * _challengeKeys.length * _closerKeys.length;

  static List<String> allMessages({AppStrings? strings}) {
    final copy = strings ?? AppStrings.forTesting();
    return <String>[
      for (final opener in _openerKeys)
        for (final challenge in _challengeKeys)
          for (final closer in _closerKeys)
            '${copy.text(opener)} ${copy.text(challenge)} ${copy.text(closer)}',
    ];
  }

  static List<String> shuffled({required int seed, AppStrings? strings}) {
    final messages = allMessages(strings: strings);
    messages.shuffle(Random(seed));
    return messages;
  }
}
