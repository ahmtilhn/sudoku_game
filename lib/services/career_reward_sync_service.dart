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
  Completer<void>? _idleCompleter;

  bool get syncing => _syncing;

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

  /// Ensures the latest locally recorded Career completion has been offered to
  /// the authoritative Economy V3 backend, then returns only after the sync is
  /// fully idle. This closes the short race between LocalProgressStore notifying
  /// listeners and a completion result reading the refreshed Coin balance.
  Future<void> waitForIdle() async {
    if (!_syncing) {
      await syncNow();
      return;
    }
    while (_syncing) {
      final pending = _idleCompleter;
      if (pending == null) return;
      await pending.future;
    }
  }

  Future<void> syncNow() async {
    if (_syncing) {
      _syncAgain = true;
      await waitForIdle();
      return;
    }
    final store = _store;
    if (store == null) return;

    _syncing = true;
    final idle = Completer<void>();
    _idleCompleter = idle;
    try {
      do {
        _syncAgain = false;
        await _syncVariant(store, SudokuVariant.classic9);
        await _syncVariant(store, SudokuVariant.classic16);
      } while (_syncAgain);
    } finally {
      _syncing = false;
      if (!idle.isCompleted) idle.complete();
      if (identical(_idleCompleter, idle)) _idleCompleter = null;
    }
  }

  Future<void> _syncVariant(
    LocalProgressStore store,
    SudokuVariant variant,
  ) async {
    final completedLevel = store.nextCareerLevelNumberFor(variant) - 1;
    if (completedLevel <= 0) return;

    final variantName = variant.id == SudokuVariantId.classic16
        ? 'classic16'
        : 'classic9';
    final lastSynced = _lastSyncedLevel[variant.id] ?? 0;
    if (completedLevel <= lastSynced) return;

    // Inside the same app session we know exactly which levels have already
    // synchronized, so claim any newly completed levels strictly in order.
    if (lastSynced > 0) {
      for (var level = lastSynced + 1; level <= completedLevel; level++) {
        final result = await _economy.claimCareer(
          level: level,
          variant: variantName,
        );
        if (result == null) return;
        _lastSyncedLevel[variant.id] = level;
      }
      return;
    }

    // Preserve the existing migration behavior for installs that already had
    // local Career progress before Economy V3: first try only the current local
    // level instead of retroactively granting every historical level.
    final currentResult = await _economy.claimCareer(
      level: completedLevel,
      variant: variantName,
    );
    if (currentResult != null) {
      _lastSyncedLevel[variant.id] = completedLevel;
      return;
    }

    // If the server says there is a sequence gap, a previous reward claim is
    // already recorded server-side but one or more later levels were missed.
    // Replaying from level 1 is safe: already rewarded levels are idempotent
    // replays, while the first genuinely missing level is then claimed in order.
    if (_economy.errorCode != 'career_sequence_gap') return;

    for (var level = 1; level <= completedLevel; level++) {
      final result = await _economy.claimCareer(
        level: level,
        variant: variantName,
      );
      if (result == null) return;
      _lastSyncedLevel[variant.id] = level;
    }
  }
}
