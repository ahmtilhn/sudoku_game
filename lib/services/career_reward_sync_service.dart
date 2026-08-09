import 'dart:async';

import '../data/local_progress_store.dart';
import '../domain/sudoku_variant.dart';
import 'economy_v3_service.dart';

class CareerRewardSyncService {
  CareerRewardSyncService._();

  static final CareerRewardSyncService instance = CareerRewardSyncService._();

  final EconomyV3Service _economy = EconomyV3Service.instance;
  final Map<SudokuVariantId, int> _lastSyncedLevel = <SudokuVariantId, int>{};

  LocalProgressStore? _store;
  bool _syncing = false;
  bool _syncAgain = false;

  void bind(LocalProgressStore store) {
    if (identical(_store, store)) return;
    _store?.removeListener(_onProgressChanged);
    _store = store;
    store.addListener(_onProgressChanged);
    unawaited(syncNow());
  }

  void _onProgressChanged() {
    unawaited(syncNow());
  }

  Future<void> syncNow() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    final store = _store;
    if (store == null) return;

    _syncing = true;
    try {
      do {
        _syncAgain = false;
        await _syncVariant(store, SudokuVariant.classic9);
        await _syncVariant(store, SudokuVariant.classic16);
      } while (_syncAgain);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncVariant(
    LocalProgressStore store,
    SudokuVariant variant,
  ) async {
    final completedLevel = store.nextCareerLevelNumberFor(variant) - 1;
    if (completedLevel <= 0) return;
    final lastSynced = _lastSyncedLevel[variant.id] ?? 0;
    if (completedLevel <= lastSynced) return;

    final result = await _economy.claimCareer(
      level: completedLevel,
      variant: variant.id == SudokuVariantId.classic16
          ? 'classic16'
          : 'classic9',
    );
    if (result != null) {
      _lastSyncedLevel[variant.id] = completedLevel;
    }
  }
}
