import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/online_duel_emote_catalog.dart';

class OnlineDuelEmoteLoadoutService extends ChangeNotifier {
  OnlineDuelEmoteLoadoutService._();

  static final OnlineDuelEmoteLoadoutService instance =
      OnlineDuelEmoteLoadoutService._();

  static const int maxSlots = 8;
  static const String _storageKey = 'online_duel_emote_loadout_v1';

  final List<String> _selectedIds = List<String>.from(
    onlineDuelDefaultEmoteIds,
  );

  Future<void>? _initializing;
  bool _initialized = false;

  bool get initialized => _initialized;
  List<String> get selectedIds => List<String>.unmodifiable(_selectedIds);
  List<OnlineDuelEmoteDefinition> get selectedEmotes =>
      onlineDuelEmotesForIds(_selectedIds);
  int get selectedCount => _selectedIds.length;
  bool get isFull => _selectedIds.length >= maxSlots;

  Future<void> initialize() {
    return _initializing ??= _load();
  }

  bool isSelected(String emoteId) => _selectedIds.contains(emoteId);

  int slotOf(String emoteId) {
    final index = _selectedIds.indexOf(emoteId);
    return index < 0 ? -1 : index + 1;
  }

  Future<bool> toggle(String emoteId) async {
    await initialize();
    if (!onlineDuelEmoteCatalogIds.contains(emoteId)) return false;

    if (_selectedIds.contains(emoteId)) {
      if (_selectedIds.length <= 1) return false;
      _selectedIds.remove(emoteId);
      await _persist();
      notifyListeners();
      return true;
    }

    if (isFull) return false;
    _selectedIds.add(emoteId);
    await _persist();
    notifyListeners();
    return true;
  }

  Future<bool> equip(String emoteId) async {
    await initialize();
    if (!onlineDuelEmoteCatalogIds.contains(emoteId)) return false;
    if (_selectedIds.contains(emoteId)) return true;
    if (isFull) return false;

    _selectedIds.add(emoteId);
    await _persist();
    notifyListeners();
    return true;
  }

  Future<bool> unequip(String emoteId) async {
    await initialize();
    if (!_selectedIds.contains(emoteId)) return true;
    if (_selectedIds.length <= 1) return false;

    _selectedIds.remove(emoteId);
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    await initialize();
    if (oldIndex < 0 || oldIndex >= _selectedIds.length) return;

    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0) target = 0;
    if (target >= _selectedIds.length) target = _selectedIds.length - 1;
    if (target == oldIndex) return;

    final id = _selectedIds.removeAt(oldIndex);
    _selectedIds.insert(target, id);
    await _persist();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    await initialize();
    _selectedIds
      ..clear()
      ..addAll(onlineDuelDefaultEmoteIds.take(maxSlots));
    await _persist();
    notifyListeners();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getStringList(_storageKey);
    if (saved != null) {
      final normalized = <String>[];
      for (final rawId in saved) {
        final id = rawId.trim();
        if (id.isEmpty ||
            !onlineDuelEmoteCatalogIds.contains(id) ||
            normalized.contains(id)) {
          continue;
        }
        normalized.add(id);
        if (normalized.length == maxSlots) break;
      }
      if (normalized.isNotEmpty) {
        _selectedIds
          ..clear()
          ..addAll(normalized);
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_storageKey, _selectedIds);
  }
}
