#!/usr/bin/env python3
"""Centralize user-visible copy outside normal widget literals.

Covers local/push notifications, reminder copy, rank accessibility text and
backend notification payloads. The migration is idempotent so it can safely run
again after nearby edits.
"""

from __future__ import annotations

import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_STRINGS = ROOT / 'lib/localization/app_strings.dart'
IOS_CATALOG = ROOT / 'assets/localization/Localizable.xcstrings'
ANDROID_STRINGS = ROOT / 'android/app/src/main/res/values/strings.xml'

STRINGS: dict[str, str] = {
    'online_challenges_channel_name': 'Online challenges',
    'online_challenges_channel_description': 'Invitations and updates for online Sudoku challenges and rematches.',
    'push_challenge_accepted_title': 'Challenge accepted',
    'push_challenge_accepted_body': 'Your opponent accepted. The duel room is ready.',
    'push_challenge_declined_title': 'Challenge declined',
    'push_challenge_declined_body': 'Your opponent declined the Sudoku challenge.',
    'push_challenge_cancelled_title': 'Challenge cancelled',
    'push_challenge_cancelled_body': 'The pending Sudoku challenge was cancelled.',
    'push_challenge_updated_title': 'Challenge updated',
    'push_challenge_updated_body': 'Your Sudoku challenge status changed.',
    'push_friend_request_title': 'New friend request',
    'push_friend_request_body': 'A player sent you a friend request.',
    'push_friend_accepted_title': 'Friend request accepted',
    'push_friend_accepted_body': 'Your friend request was accepted.',
    'push_friend_declined_title': 'Friend request declined',
    'push_friend_declined_body': 'Your friend request was declined.',
    'push_friend_updated_title': 'Friend request updated',
    'push_friend_updated_body': 'Your friend request was updated.',
    'push_rematch_title': 'Rematch invitation',
    'push_rematch_body': 'A player wants to play again. Open Sudoku Duel to respond.',
    'push_challenge_title': 'New Sudoku challenge',
    'push_challenge_body': 'A player challenged you. Open Sudoku Duel to respond.',
    'push_online_invitation_title': 'Online invitation',
    'push_online_invitation_body': 'Open Sudoku Duel to continue.',
    'notification_setup_failed': 'Notification setup failed. Please try again.',
    'notification_permission_denied': 'Notification permission was denied.',
    'notification_token_unavailable': 'Notification registration is temporarily unavailable.',
    'notification_registration_failed': 'Notification registration failed. Please try again.',
    'rank_emblem_semantics': '%1s rank emblem',
    'reminder_opener_01': 'Your next Sudoku is waiting.',
    'reminder_opener_02': 'A fresh grid just challenged you.',
    'reminder_opener_03': 'Your brain deserves a quick workout.',
    'reminder_opener_04': 'The board is ready when you are.',
    'reminder_opener_05': 'A new puzzle wants your attention.',
    'reminder_opener_06': 'Today’s logic challenge has arrived.',
    'reminder_opener_07': 'Your next winning streak starts here.',
    'reminder_opener_08': 'One clever move can change the board.',
    'reminder_opener_09': 'The Sudoku arena is calling.',
    'reminder_opener_10': 'A quiet challenge is ready for you.',
    'reminder_opener_11': 'Your daily focus break is here.',
    'reminder_opener_12': 'Another puzzle is ready to be conquered.',
    'reminder_challenge_01': 'Can you finish without a single mistake?',
    'reminder_challenge_02': 'Can you beat your latest performance?',
    'reminder_challenge_03': 'Try a harder difficulty this time.',
    'reminder_challenge_04': 'See how far pure logic can take you.',
    'reminder_challenge_05': 'Protect your three-mistake limit.',
    'reminder_challenge_06': 'Build a cleaner winning streak today.',
    'reminder_challenge_07': 'Find the first hidden number now.',
    'reminder_challenge_08': 'Challenge yourself before someone else does.',
    'reminder_challenge_09': 'Prove that this grid cannot stop you.',
    'reminder_challenge_10': 'Turn a few focused minutes into a win.',
    'reminder_challenge_11': 'Solve one row and let momentum take over.',
    'reminder_challenge_12': 'Show the board who is in control.',
    'reminder_closer_01': 'Open Sudoku Duel and take the first move.',
    'reminder_closer_02': 'Your next victory may be one tap away.',
    'reminder_closer_03': 'Start now and keep your streak alive.',
    'reminder_closer_04': 'The challenge only begins when you open it.',
    'reminder_closer_05': 'A focused minute is all you need to begin.',
    'reminder_closer_06': 'Step into the grid and prove it.',
    'reminder_closer_07': 'Play now before the puzzle wins by default.',
    'reminder_closer_08': 'Tap in and claim today’s challenge.',
}


def dart_escape(value: str) -> str:
    return value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n')


def ensure_catalogs() -> None:
    source = APP_STRINGS.read_text(encoding='utf-8')
    existing = set(re.findall(r"^\s*'([a-z0-9_]+)'\s*:", source, re.MULTILINE))
    missing = [(key, value) for key, value in STRINGS.items() if key not in existing]
    if missing:
        marker = "    'empty': 'Empty',\n"
        if marker not in source:
            raise RuntimeError('app_strings insertion marker not found')
        block = ''.join(f"    '{key}': '{dart_escape(value)}',\n" for key, value in missing)
        APP_STRINGS.write_text(source.replace(marker, block + marker, 1), encoding='utf-8')

    catalog = json.loads(IOS_CATALOG.read_text(encoding='utf-8'))
    strings = catalog.setdefault('strings', {})
    changed = False
    for key, value in STRINGS.items():
        if key not in strings:
            strings[key] = {
                'localizations': {
                    'en': {'stringUnit': {'state': 'translated', 'value': value}},
                },
            }
            changed = True
    if changed:
        IOS_CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    android = ANDROID_STRINGS.read_text(encoding='utf-8')
    android_keys = set(re.findall(r'<string\s+name="([a-z0-9_]+)"', android))
    additions = []
    for key, value in STRINGS.items():
        if key in android_keys:
            continue
        escaped = html.escape(value, quote=False).replace("'", "\\'")
        additions.append(f'    <string name="{key}" formatted="false">{escaped}</string>\n')
    if additions:
        ANDROID_STRINGS.write_text(
            android.replace('</resources>', ''.join(additions) + '</resources>', 1),
            encoding='utf-8',
        )


def migrate_reminders() -> None:
    catalog_path = ROOT / 'lib/services/reminder_message_catalog.dart'
    catalog_path.write_text(
        """import 'dart:math';

import '../localization/app_strings.dart';

class ReminderMessageCatalog {
  const ReminderMessageCatalog._();

  static const List<String> _openerKeys = <String>[
    'reminder_opener_01', 'reminder_opener_02', 'reminder_opener_03',
    'reminder_opener_04', 'reminder_opener_05', 'reminder_opener_06',
    'reminder_opener_07', 'reminder_opener_08', 'reminder_opener_09',
    'reminder_opener_10', 'reminder_opener_11', 'reminder_opener_12',
  ];
  static const List<String> _challengeKeys = <String>[
    'reminder_challenge_01', 'reminder_challenge_02', 'reminder_challenge_03',
    'reminder_challenge_04', 'reminder_challenge_05', 'reminder_challenge_06',
    'reminder_challenge_07', 'reminder_challenge_08', 'reminder_challenge_09',
    'reminder_challenge_10', 'reminder_challenge_11', 'reminder_challenge_12',
  ];
  static const List<String> _closerKeys = <String>[
    'reminder_closer_01', 'reminder_closer_02', 'reminder_closer_03',
    'reminder_closer_04', 'reminder_closer_05', 'reminder_closer_06',
    'reminder_closer_07', 'reminder_closer_08',
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
""",
        encoding='utf-8',
    )

    path = ROOT / 'lib/services/reminder_notification_service.dart'
    source = path.read_text(encoding='utf-8')
    source = source.replace('  int _seed = 1;\n', '  int _seed = 1;\n  AppStrings? _strings;\n')
    source = source.replace(
        '  Future<void> initialize() async {\n',
        '  Future<void> initialize() async {\n    _strings ??= await AppStrings.load();\n',
    )
    source = source.replace(
        '    final messages = ReminderMessageCatalog.shuffled(seed: _seed ^ daySeed);',
        '    final strings = _strings ??= await AppStrings.load();\n    final messages = ReminderMessageCatalog.shuffled(\n      seed: _seed ^ daySeed,\n      strings: strings,\n    );',
    )
    source = source.replace("        AppStrings.english['daily_sudoku_challenges']!,", "        strings.text('daily_sudoku_challenges'),")
    source = source.replace("            AppStrings.english['daily_sudoku_challenges_channel']!,", "            strings.text('daily_sudoku_challenges_channel'),")
    source = source.replace("        title: AppStrings.english['app_name']!,", "        title: strings.text('app_name'),")
    path.write_text(source, encoding='utf-8')


def migrate_rank_semantics() -> None:
    path = ROOT / 'lib/widgets/rank_emblem.dart'
    source = path.read_text(encoding='utf-8')
    if "../localization/app_strings.dart" not in source:
        source = source.replace(
            "import 'package:flutter/material.dart';\n\n",
            "import 'package:flutter/material.dart';\n\nimport '../localization/app_strings.dart';\n",
            1,
        )
    source = source.replace(
        "semanticLabel: semanticLabel ?? '${tier.label} rank emblem',",
        "semanticLabel: semanticLabel ??\n            context.tr('rank_emblem_semantics', <Object>[\n              context.tr('rank_${tier.key}'),\n            ]),",
    )
    path.write_text(source, encoding='utf-8')


def migrate_push_client() -> None:
    path = ROOT / 'lib/services/push_notification_service.dart'
    source = path.read_text(encoding='utf-8')
    if "../localization/app_strings.dart" not in source:
        source = source.replace(
            "import 'package:shared_preferences/shared_preferences.dart';\n\n",
            "import 'package:shared_preferences/shared_preferences.dart';\n\nimport '../localization/app_strings.dart';\n",
            1,
        )
    source = source.replace('required this.defaultTitle,\n    required this.defaultBody,', 'required this.defaultTitleKey,\n    required this.defaultBodyKey,')
    source = source.replace('final String defaultTitle;\n  final String defaultBody;', 'final String defaultTitleKey;\n  final String defaultBodyKey;')

    replacements = {
        "defaultTitle: 'Challenge accepted',\n        defaultBody: 'Your opponent accepted. The duel room is ready.',": "defaultTitleKey: 'push_challenge_accepted_title',\n        defaultBodyKey: 'push_challenge_accepted_body',",
        "defaultTitle: status == 'declined'\n          ? 'Challenge declined'\n          : status == 'cancelled'\n          ? 'Challenge cancelled'\n          : 'Challenge updated',": "defaultTitleKey: status == 'declined'\n          ? 'push_challenge_declined_title'\n          : status == 'cancelled'\n          ? 'push_challenge_cancelled_title'\n          : 'push_challenge_updated_title',",
        "defaultBody: status == 'declined'\n          ? 'Your opponent declined the Sudoku challenge.'\n          : status == 'cancelled'\n          ? 'The pending Sudoku challenge was cancelled.'\n          : 'Your Sudoku challenge status changed.',": "defaultBodyKey: status == 'declined'\n          ? 'push_challenge_declined_body'\n          : status == 'cancelled'\n          ? 'push_challenge_cancelled_body'\n          : 'push_challenge_updated_body',",
        "defaultTitle: 'New friend request',\n        defaultBody: 'A player sent you a friend request.',": "defaultTitleKey: 'push_friend_request_title',\n        defaultBodyKey: 'push_friend_request_body',",
        "defaultTitle: status == 'accepted'\n            ? 'Friend request accepted'\n            : 'Friend request updated',": "defaultTitleKey: status == 'accepted'\n            ? 'push_friend_accepted_title'\n            : status == 'declined'\n            ? 'push_friend_declined_title'\n            : 'push_friend_updated_title',",
        "defaultBody: status == 'accepted'\n            ? 'Your friend request was accepted.'\n            : 'Your friend request was updated.',": "defaultBodyKey: status == 'accepted'\n            ? 'push_friend_accepted_body'\n            : status == 'declined'\n            ? 'push_friend_declined_body'\n            : 'push_friend_updated_body',",
        "defaultTitle: 'Rematch invitation',\n      defaultBody:\n          'A player wants to play again. Open Sudoku Duel to respond.',": "defaultTitleKey: 'push_rematch_title',\n      defaultBodyKey: 'push_rematch_body',",
        "defaultTitle: 'New Sudoku challenge',\n      defaultBody: 'A player challenged you. Open Sudoku Duel to respond.',": "defaultTitleKey: 'push_challenge_title',\n      defaultBodyKey: 'push_challenge_body',",
        "defaultTitle: 'Online invitation',\n        defaultBody: 'Open Sudoku Duel to continue.',": "defaultTitleKey: 'push_online_invitation_title',\n        defaultBodyKey: 'push_online_invitation_body',",
    }
    for old, new in replacements.items():
        source = source.replace(old, new)

    source = source.replace('  bool _automaticSocialUiAllowed = false;\n', '  bool _automaticSocialUiAllowed = false;\n  AppStrings? _strings;\n')
    source = source.replace(
        '      await FirebaseRuntimeConfig.initializeIfConfigured();\n',
        '      await FirebaseRuntimeConfig.initializeIfConfigured();\n      _strings ??= await AppStrings.load();\n',
        1,
    )
    source = source.replace('lastRegistrationError.value = error.toString();', "lastRegistrationError.value = _localized('notification_setup_failed');", 1)
    source = source.replace("lastRegistrationError.value = 'Notification permission was denied.';", "lastRegistrationError.value = _localized('notification_permission_denied');")
    source = source.replace('lastRegistrationError.value = error.toString();', "lastRegistrationError.value = _localized('notification_registration_failed');", 1)
    source = source.replace("lastRegistrationError.value = 'FCM registration token is unavailable.';", "lastRegistrationError.value = _localized('notification_token_unavailable');")
    source = source.replace('lastRegistrationError.value = error.message;', "lastRegistrationError.value = _localized('notification_registration_failed');")
    source = source.replace('lastRegistrationError.value = error.toString();', "lastRegistrationError.value = _localized('notification_registration_failed');")

    source = source.replace(
        "const AndroidNotificationChannel(\n              _challengeChannelId,\n              'Online challenges',\n              description:\n                  'Invitations and updates for online Sudoku challenges and rematches.',",
        "AndroidNotificationChannel(\n              _challengeChannelId,\n              _localized('online_challenges_channel_name'),\n              description: _localized('online_challenges_channel_description'),",
    )
    source = source.replace('title: message.notification?.title ?? target.defaultTitle,', "title: message.notification?.title ?? _localized(target.defaultTitleKey),")
    source = source.replace('body: message.notification?.body ?? target.defaultBody,', "body: message.notification?.body ?? _localized(target.defaultBodyKey),")
    source = source.replace('notificationDetails: const NotificationDetails(', 'notificationDetails: NotificationDetails(')
    source = source.replace(
        "AndroidNotificationDetails(\n          _challengeChannelId,\n          'Online challenges',\n          channelDescription:\n              'Invitations and updates for online Sudoku challenges and rematches.',",
        "AndroidNotificationDetails(\n          _challengeChannelId,\n          _localized('online_challenges_channel_name'),\n          channelDescription: _localized('online_challenges_channel_description'),",
    )
    source = source.replace('        iOS: DarwinNotificationDetails(', '        iOS: const DarwinNotificationDetails(')
    marker = '  bool _isAuthorized(AuthorizationStatus status) {'
    if "String _localized(String key)" not in source and marker in source:
        source = source.replace(marker, "  String _localized(String key) =>\n      _strings?.text(key) ?? AppStrings.english[key] ?? key;\n\n" + marker, 1)
    path.write_text(source, encoding='utf-8')


def localized_platform_payload(message_expr: str, tag_expr: str) -> str:
    return f"""message: {{
              token: device.token,
              data: {message_expr}.data,
              android: {{
                priority: 'high',
                notification: {{
                  channel_id: 'online_challenges',
                  tag: {tag_expr},
                  sound: 'default',
                  title_loc_key: {message_expr}.titleKey,
                  body_loc_key: {message_expr}.bodyKey,
                }},
              }},
              apns: {{
                headers: {{ 'apns-priority': '10' }},
                payload: {{
                  aps: {{
                    alert: {{
                      'title-loc-key': {message_expr}.titleKey,
                      'loc-key': {message_expr}.bodyKey,
                    }},
                    sound: 'default',
                    badge: 1,
                    'thread-id': 'online-challenges',
                  }},
                }},
              }},
            }}"""


def migrate_push_backend() -> None:
    push = ROOT / 'backend/social_worker/src/push_notifications.ts'
    source = push.read_text(encoding='utf-8')
    source = source.replace('  title: string;\n  body: string;', '  titleKey: string;\n  bodyKey: string;')
    old = """message: {
              token: device.token,
              notification: { title: message.title, body: message.body },
              data: message.data,
              android: {
                priority: 'high',
                notification: {
                  channel_id: 'online_challenges',
                  tag: message.tag,
                  sound: 'default',
                },
              },
              apns: {
                headers: { 'apns-priority': '10' },
                payload: {
                  aps: {
                    sound: 'default',
                    badge: 1,
                    'thread-id': 'online-challenges',
                  },
                },
              },
            }"""
    source = source.replace(old, localized_platform_payload('message', 'message.tag'))
    push.write_text(source, encoding='utf-8')

    friend = ROOT / 'backend/social_worker/src/friend_notifications.ts'
    source = friend.read_text(encoding='utf-8')
    source = re.sub(
        r"title: 'New friend request',\n\s*body: `\$\{requester\.display_name\} sent you a friend request\.`,",
        "titleKey: 'push_friend_request_title',\n    bodyKey: 'push_friend_request_body',",
        source,
    )
    source = re.sub(
        r"title: accepted \? 'Friend request accepted' : 'Friend request declined',\n\s*body: accepted\n\s*\? `\$\{responder\.display_name\} accepted your friend request\.`\n\s*: `\$\{responder\.display_name\} declined your friend request\.`,",
        "titleKey: accepted\n      ? 'push_friend_accepted_title'\n      : 'push_friend_declined_title',\n    bodyKey: accepted\n      ? 'push_friend_accepted_body'\n      : 'push_friend_declined_body',",
        source,
    )
    friend.write_text(source, encoding='utf-8')

    entry = ROOT / 'backend/social_worker/src/entry.ts'
    source = entry.read_text(encoding='utf-8')
    source = source.replace("title: 'Rematch invitation',\n      body: `${senderName} wants to play again. You have 10 seconds to respond.`,", "titleKey: 'push_rematch_title',\n      bodyKey: 'push_rematch_body',")
    source = source.replace("    const senderName = String(sender?.displayName ?? 'A player');\n", '')
    entry.write_text(source, encoding='utf-8')

    index = ROOT / 'backend/social_worker/src/index.ts'
    source = index.read_text(encoding='utf-8')
    source = source.replace('  title: string;\n  body: string;', '  titleKey: string;\n  bodyKey: string;')
    old = """message: {
              token: device.token,
              notification: { title: message.title, body: message.body },
              data: message.data,
              android: {
                priority: 'high',
                notification: {
                  channel_id: 'online_challenges',
                  tag: `challenge_${message.data.challengeId ?? 'update'}`,
                  sound: 'default',
                },
              },
              apns: {
                headers: { 'apns-priority': '10' },
                payload: {
                  aps: {
                    sound: 'default',
                    badge: 1,
                    'thread-id': 'online-challenges',
                  },
                },
              },
            }"""
    source = source.replace(old, localized_platform_payload('message', "`challenge_${message.data.challengeId ?? 'update'}`"))
    source = source.replace("title: 'New Sudoku challenge',\n      body: `${current.display_name} challenged you on ${difficulty}.`,", "titleKey: 'push_challenge_title',\n      bodyKey: 'push_challenge_body',")
    source = source.replace("title: 'Challenge cancelled',\n        body: `${current.display_name} cancelled the Sudoku challenge.`,", "titleKey: 'push_challenge_cancelled_title',\n        bodyKey: 'push_challenge_cancelled_body',")
    source = source.replace("title: 'Challenge declined',\n        body: `${current.display_name} declined your Sudoku challenge.`,", "titleKey: 'push_challenge_declined_title',\n        bodyKey: 'push_challenge_declined_body',")
    source = source.replace("title: 'Challenge accepted',\n        body: `${current.display_name} accepted your Sudoku challenge.`,", "titleKey: 'push_challenge_accepted_title',\n        bodyKey: 'push_challenge_accepted_body',")
    index.write_text(source, encoding='utf-8')


def wire_ios_catalog_into_bundle() -> None:
    path = ROOT / 'ios/Runner.xcodeproj/project.pbxproj'
    source = path.read_text(encoding='utf-8')
    if 'Localizable.xcstrings in Resources' in source:
        return
    build_id = '6D7A0C3F2D8F4A6A9E4D2B21'
    file_id = '6D7A0C3E2D8F4A6A9E4D2B21'
    source = source.replace(
        '/* Begin PBXBuildFile section */\n',
        '/* Begin PBXBuildFile section */\n'
        f'\t\t{build_id} /* Localizable.xcstrings in Resources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* Localizable.xcstrings */; }};\n',
        1,
    )
    source = source.replace(
        '/* Begin PBXFileReference section */\n',
        '/* Begin PBXFileReference section */\n'
        f'\t\t{file_id} /* Localizable.xcstrings */ = {{isa = PBXFileReference; lastKnownFileType = text.json.xcstrings; name = Localizable.xcstrings; path = ../../assets/localization/Localizable.xcstrings; sourceTree = "<group>"; }};\n',
        1,
    )
    source = source.replace(
        '\t\t\t\t97C146FA1CF9000F007C117D /* Main.storyboard */,\n',
        f'\t\t\t\t{file_id} /* Localizable.xcstrings */,\n\t\t\t\t97C146FA1CF9000F007C117D /* Main.storyboard */,\n',
        1,
    )
    source = source.replace(
        '\t\t\t\t97C147011CF9000F007C117D /* LaunchScreen.storyboard in Resources */,\n',
        f'\t\t\t\t{build_id} /* Localizable.xcstrings in Resources */,\n\t\t\t\t97C147011CF9000F007C117D /* LaunchScreen.storyboard in Resources */,\n',
        1,
    )
    path.write_text(source, encoding='utf-8')


def main() -> int:
    ensure_catalogs()
    migrate_reminders()
    migrate_rank_semantics()
    migrate_push_client()
    migrate_push_backend()
    wire_ios_catalog_into_bundle()
    print(f'Centralized {len(STRINGS)} non-widget user-facing strings.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
