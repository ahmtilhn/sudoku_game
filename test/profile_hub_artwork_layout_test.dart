import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile hub action artwork keeps profile and emote fill behavior', () {
    final source = File(
      'lib/features/social/profile_hub_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final fillArtwork ='));
    expect(source, contains('tab.tab == _ProfileTab.customize'));
    expect(source, contains('tab.tab == _ProfileTab.emotes'));
    expect(source, contains('child: ClipRRect('));
    expect(source, contains('fit: fillArtwork ? BoxFit.cover : BoxFit.contain'));
    expect(
      source,
      contains('physics: const NeverScrollableScrollPhysics()'),
    );
  });

  test('profile hub artwork is contained by responsive action cards', () {
    final source = File(
      'lib/features/social/profile_hub_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final artworkSize = narrow ? 34.0 : 42.0;'));
    expect(
      source,
      contains('childAspectRatio: constraints.maxHeight < 250 ? 1.8 : 1.25'),
    );
    expect(source, contains('BoxFit.contain'));
    expect(
      source,
      isNot(contains('tab.tab == _ProfileTab.leaderboards ? 54.0')),
    );
  });
}
