import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sudoku_game/models/online_duel_emote_catalog.dart';
import 'package:sudoku_game/services/online_duel_emote_loadout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('uses the eight legacy emotes as the default loadout', () async {
    final service = OnlineDuelEmoteLoadoutService();

    await service.initialize();

    expect(service.selectedIds, onlineDuelDefaultEmoteIds);
    expect(service.selectedCount, OnlineDuelEmoteLoadoutService.maxSlots);
    expect(service.isFull, isTrue);
  });

  test('persists selection order and rejects unknown emotes', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'online_duel_emote_loadout_v1': <String>['gg', 'ez', 'laugh'],
    });
    final service = OnlineDuelEmoteLoadoutService();

    await service.initialize();

    expect(service.selectedIds, <String>['gg', 'ez', 'laugh']);
    expect(await service.equip('not-real'), isFalse);
    expect(await service.equip('bruh'), isTrue);
    expect(service.selectedIds, <String>['gg', 'ez', 'laugh', 'bruh']);

    await service.reorder(3, 0);
    expect(service.selectedIds, <String>['bruh', 'gg', 'ez', 'laugh']);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getStringList('online_duel_emote_loadout_v1'),
      <String>['bruh', 'gg', 'ez', 'laugh'],
    );
  });

  test('never allows more than eight equipped emotes', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'online_duel_emote_loadout_v1': <String>['smile'],
    });
    final service = OnlineDuelEmoteLoadoutService();
    await service.initialize();

    for (final id in <String>[
      'laugh',
      'smug',
      'fire',
      'crown',
      'gg',
      'ez',
      'bruh',
    ]) {
      expect(await service.equip(id), isTrue);
    }

    expect(service.selectedCount, 8);
    expect(await service.equip('rekt'), isFalse);
    expect(service.selectedCount, 8);
  });

  test('keeps at least one quick emote equipped', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'online_duel_emote_loadout_v1': <String>['gg'],
    });
    final service = OnlineDuelEmoteLoadoutService();
    await service.initialize();

    expect(await service.unequip('gg'), isFalse);
    expect(service.selectedIds, <String>['gg']);
  });
}
