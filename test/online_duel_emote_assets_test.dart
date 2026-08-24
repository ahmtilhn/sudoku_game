import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/models/online_duel_emote_catalog.dart';

void main() {
  test('every duel emote id and artwork path is unique and bundled on disk', () {
    final ids = <String>{};
    final assetPaths = <String>{};

    for (final emote in onlineDuelEmoteCatalog) {
      expect(ids.add(emote.id), isTrue, reason: 'Duplicate id: ${emote.id}');

      final assetPath = emote.assetPath;
      expect(assetPath, isNotNull, reason: 'Missing artwork: ${emote.id}');
      expect(assetPath, isNotEmpty, reason: 'Empty artwork path: ${emote.id}');
      expect(
        assetPaths.add(assetPath!),
        isTrue,
        reason: 'Duplicate artwork path: $assetPath',
      );
      expect(
        File(assetPath).existsSync(),
        isTrue,
        reason: 'Artwork file does not exist: ${emote.id} -> $assetPath',
      );
    }
  });

  test('iconic text emotes use their intended final artwork', () {
    expect(onlineDuelEmoteById('gg')?.assetPath, 'assets/emote/gg_txt.png');
    expect(onlineDuelEmoteById('ez')?.assetPath, 'assets/emote/ez.png');
    expect(onlineDuelEmoteById('one_v_one')?.assetPath, 'assets/emote/1v1.png');
    expect(onlineDuelEmoteById('oops')?.assetPath, 'assets/emote/ooops.png');
  });
}
