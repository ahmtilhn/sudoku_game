import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile hub action artwork fills profile and emote boxes', () {
    final source = File(
      'lib/features/social/profile_hub_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final fillArtwork ='));
    expect(source, contains('tab.tab == _ProfileTab.customize'));
    expect(source, contains('tab.tab == _ProfileTab.emotes'));
    expect(source, contains('clipBehavior: Clip.antiAlias'));
    expect(source, contains('fillArtwork ? BoxFit.cover : BoxFit.contain'));
  });

  test('profile hub leaderboard artwork is larger but contained', () {
    final source = File(
      'lib/features/social/profile_hub_screen.dart',
    ).readAsStringSync();

    expect(source, contains('tab.tab == _ProfileTab.leaderboards ? 54.0'));
    expect(source, contains('tab.tab == _ProfileTab.leaderboards'));
    expect(source, contains('? 48.0'));
    expect(source, contains('BoxFit.contain'));
  });
}
