from pathlib import Path

root = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str, label: str) -> None:
    target = root / path
    source = target.read_text(encoding='utf-8')
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    target.write_text(source.replace(old, new, 1), encoding='utf-8')


# Close Scaffold and PopScope independently.
replace_once(
    'lib/features/duel/pre_match_ready_screen.dart',
    """        ),
      ),
    );
  }

  String _statusText""",
    """        ),
      ),
    ),
  );
  }

  String _statusText""",
    'pre-match PopScope closing',
)

# Merge the two generated room helpers into one authoritative path.
replace_once(
    'lib/features/social/ux_challenge_invitation_screen.dart',
    """  Future<void> _openRoom(String roomId) async {
    await _economy.refresh(showLoading: false);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) => PreMatchReadyScreen(roomId: roomId),
      ),
    );
  }

  Future<void> _openRoom(String roomId) async {
    if (!mounted) return;
    _timer?.cancel();
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) => PreMatchReadyScreen(roomId: roomId),
      ),
    );
  }
""",
    """  Future<void> _openRoom(String roomId) async {
    _timer?.cancel();
    await _economy.refresh(showLoading: false);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) => PreMatchReadyScreen(roomId: roomId),
      ),
    );
  }
""",
    'duplicate invitation room helper',
)

# Explicitly promote the nullable platform only in authoritative resync.
replace_once(
    'lib/services/platform_leaderboard_service.dart',
    """  Future<PlatformLeaderboardMirrorResult> syncAuthoritativeRatings() async {
    final platform = _resolvedPlatform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.skipped,
      );
    }
""",
    """  Future<PlatformLeaderboardMirrorResult> syncAuthoritativeRatings() async {
    final platform = _resolvedPlatform;
    if (platform == null ||
        (platform != TargetPlatform.android &&
            platform != TargetPlatform.iOS)) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.skipped,
      );
    }
""",
    'nullable authoritative platform promotion',
)

print('Challenge analyze errors fixed.')
