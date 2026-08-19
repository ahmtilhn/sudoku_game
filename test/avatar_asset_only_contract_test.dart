import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile exposes only bundled avatar choices', () {
    final profile = File(
      'lib/features/social/profile_customization_screen.dart',
    ).readAsStringSync();
    final avatar = File('lib/widgets/player_avatar.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(profile, contains('final choices = AvatarPresetCatalog.all;'));
    expect(profile, isNot(contains('PlatformGameServices')));
    expect(profile, isNot(contains("'home-profile-platform'")));
    expect(profile, isNot(contains("'Initials'")));
    expect(profile, contains('AvatarPresetCatalog.normalizeKey'));

    expect(avatar, contains('Image.asset('));
    expect(avatar, contains('AvatarPresetCatalog.assetPathForKey'));
    expect(avatar, isNot(contains('Image.memory(')));
    expect(avatar, isNot(contains('Image.network(')));

    expect(pubspec, contains('- assets/avatar/'));
  });

  test('current avatar catalog points only at the 40 pushed PNG files', () {
    expect(File('assets/avatar/avatar.png').existsSync(), isTrue);
    for (var number = 2; number <= 40; number++) {
      expect(
        File('assets/avatar/avatar ($number).png').existsSync(),
        isTrue,
        reason: 'Missing bundled avatar $number',
      );
    }

    final catalog = File(
      'lib/models/avatar_preset_catalog.dart',
    ).readAsStringSync();
    expect(catalog, contains('static const int count = 40;'));
    expect(catalog, contains("'assets/avatar/avatar.png'"));
    expect(catalog, contains("'assets/avatar/avatar (\$number).png'"));
  });
}
