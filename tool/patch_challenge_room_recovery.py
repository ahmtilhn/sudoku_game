from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}")
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


backend_old = r'''async function respondChallenge(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  current: PlayerRow,
  challengeId: string,
): Promise<Response> {
  const body = await readJson(request);
  const action = requiredString(body.action, 'action', 4, 16);
  if (action !== 'accept' && action !== 'decline') {
    throw new HttpError(400, 'Challenge action must be accept or decline.');
  }

  const challenge = await challengeById(env, challengeId);
  if (challenge.recipient_id !== current.id) throw new HttpError(403, 'Only the recipient can respond.');
  if (challenge.status !== 'pending') throw new HttpError(409, 'Challenge is no longer pending.');
  if (new Date(challenge.expires_at).getTime() <= Date.now()) {
    await env.DB.prepare(
      `UPDATE challenges SET status = 'expired', updated_at = ? WHERE id = ?`,
    )
      .bind(new Date().toISOString(), challenge.id)
      .run();
    throw new HttpError(409, 'Challenge expired.');
  }

  const roomId = action === 'accept' ? crypto.randomUUID() : null;
  const status = action === 'accept' ? 'accepted' : 'declined';
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE challenges SET status = ?, room_id = ?, updated_at = ?
     WHERE id = ? AND status = 'pending'`,
  )
    .bind(status, roomId, now, challenge.id)
    .run();
  if (action === 'accept' && roomId) {
    await createMatchRow(env, {
      roomId,
      challengeId: challenge.id,
      mode: 'friendly',
      difficulty: challenge.difficulty,
      playerAId: challenge.challenger_id,
      playerBId: challenge.recipient_id,
      now,
    });
  }

  ctx.waitUntil(
    sendPlayerNotification(env, challenge.challenger_id, {
      title: status === 'accepted' ? 'Challenge accepted' : 'Challenge declined',
      body:
        status === 'accepted'
          ? `${current.display_name} accepted your Sudoku challenge.`
          : `${current.display_name} declined your Sudoku challenge.`,
      data: {
        type: 'challenge_response',
        challengeId: challenge.id,
        status,
        roomId: roomId ?? '',
      },
    }),
  );

  const updated = await challengeById(env, challenge.id);
  return reply(env, await challengeJson(env, updated));
}
'''

backend_new = r'''async function respondChallenge(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  current: PlayerRow,
  challengeId: string,
): Promise<Response> {
  const body = await readJson(request);
  const action = requiredString(body.action, 'action', 4, 16);
  if (action !== 'accept' && action !== 'decline') {
    throw new HttpError(400, 'Challenge action must be accept or decline.');
  }

  const challenge = await challengeById(env, challengeId);
  if (challenge.recipient_id !== current.id) {
    throw new HttpError(403, 'Only the recipient can respond.');
  }

  if (action === 'decline') {
    if (challenge.status === 'declined') {
      return reply(env, await challengeJson(env, challenge));
    }
    if (challenge.status !== 'pending') {
      throw new HttpError(409, 'Challenge is no longer pending.');
    }
    if (new Date(challenge.expires_at).getTime() <= Date.now()) {
      await env.DB.prepare(
        `UPDATE challenges SET status = 'expired', updated_at = ? WHERE id = ?`,
      )
        .bind(new Date().toISOString(), challenge.id)
        .run();
      throw new HttpError(409, 'Challenge expired.');
    }

    const now = new Date().toISOString();
    await env.DB.prepare(
      `UPDATE challenges SET status = 'declined', room_id = NULL, updated_at = ?
       WHERE id = ? AND status = 'pending'`,
    )
      .bind(now, challenge.id)
      .run();
    ctx.waitUntil(
      sendPlayerNotification(env, challenge.challenger_id, {
        title: 'Challenge declined',
        body: `${current.display_name} declined your Sudoku challenge.`,
        data: {
          type: 'challenge_response',
          challengeId: challenge.id,
          status: 'declined',
          roomId: '',
        },
      }),
    );
    const declined = await challengeById(env, challenge.id);
    return reply(env, await challengeJson(env, declined));
  }

  if (challenge.status !== 'pending' && challenge.status !== 'accepted') {
    throw new HttpError(409, 'Challenge is no longer available.');
  }
  if (
    challenge.status === 'pending' &&
    new Date(challenge.expires_at).getTime() <= Date.now()
  ) {
    await env.DB.prepare(
      `UPDATE challenges SET status = 'expired', updated_at = ? WHERE id = ?`,
    )
      .bind(new Date().toISOString(), challenge.id)
      .run();
    throw new HttpError(409, 'Challenge expired.');
  }

  const transitionedToAccepted = challenge.status === 'pending';
  if (transitionedToAccepted) {
    await env.DB.prepare(
      `UPDATE challenges SET status = 'accepted', room_id = COALESCE(room_id, ?), updated_at = ?
       WHERE id = ? AND status = 'pending'`,
    )
      .bind(crypto.randomUUID(), new Date().toISOString(), challenge.id)
      .run();
  }

  const accepted = await challengeById(env, challenge.id);
  if (accepted.status !== 'accepted') {
    throw new HttpError(409, 'Challenge could not be accepted.');
  }
  const roomId = await ensureAcceptedChallengeMatch(env, accepted);

  if (transitionedToAccepted) {
    ctx.waitUntil(
      sendPlayerNotification(env, challenge.challenger_id, {
        title: 'Challenge accepted',
        body: `${current.display_name} accepted your Sudoku challenge.`,
        data: {
          type: 'challenge_response',
          challengeId: challenge.id,
          status: 'accepted',
          roomId,
        },
      }),
    );
  }

  const updated = await challengeById(env, challenge.id);
  return reply(env, await challengeJson(env, updated));
}
'''

replace_once("backend/social_worker/src/index.ts", backend_old, backend_new)

active_old = r'''async function activeMatch(env: Env, current: PlayerRow): Promise<Response> {
  const match = await env.DB.prepare(
    `SELECT * FROM matches
     WHERE (player_a_id = ? OR player_b_id = ?)
       AND status IN ('waiting', 'countdown', 'active', 'paused')
     ORDER BY created_at DESC
     LIMIT 1`,
  )
    .bind(current.id, current.id)
    .first<Record<string, unknown>>();
  return reply(env, { match: match ? publicMatch(match, current.id) : null });
}
'''

active_new = r'''async function activeMatch(env: Env, current: PlayerRow): Promise<Response> {
  let match = await env.DB.prepare(
    `SELECT * FROM matches
     WHERE (player_a_id = ? OR player_b_id = ?)
       AND status IN ('waiting', 'countdown', 'active', 'paused')
     ORDER BY created_at DESC
     LIMIT 1`,
  )
    .bind(current.id, current.id)
    .first<Record<string, unknown>>();

  if (!match) {
    const acceptedChallenge = await env.DB.prepare(
      `SELECT * FROM challenges
       WHERE (challenger_id = ? OR recipient_id = ?)
         AND status = 'accepted'
       ORDER BY updated_at DESC
       LIMIT 1`,
    )
      .bind(current.id, current.id)
      .first<ChallengeRow>();
    if (acceptedChallenge) {
      const roomId = await ensureAcceptedChallengeMatch(env, acceptedChallenge);
      match = await env.DB.prepare(
        `SELECT * FROM matches WHERE room_id = ? LIMIT 1`,
      )
        .bind(roomId)
        .first<Record<string, unknown>>();
    }
  }

  return reply(env, { match: match ? publicMatch(match, current.id) : null });
}
'''

replace_once("backend/social_worker/src/index.ts", active_old, active_new)

helper_anchor = r'''async function createMatchRow(
  env: Env,
  input: {
'''
helper = r'''async function ensureAcceptedChallengeMatch(
  env: Env,
  challenge: ChallengeRow,
): Promise<string> {
  const existing = await env.DB.prepare(
    `SELECT room_id FROM matches WHERE challenge_id = ? LIMIT 1`,
  )
    .bind(challenge.id)
    .first<{ room_id: string }>();
  if (existing?.room_id) {
    if (challenge.room_id !== existing.room_id || challenge.status !== 'accepted') {
      await env.DB.prepare(
        `UPDATE challenges SET status = 'accepted', room_id = ?, updated_at = ? WHERE id = ?`,
      )
        .bind(existing.room_id, new Date().toISOString(), challenge.id)
        .run();
    }
    return existing.room_id;
  }

  const roomId = challenge.room_id || crypto.randomUUID();
  const now = new Date().toISOString();
  await createMatchRow(env, {
    roomId,
    challengeId: challenge.id,
    mode: 'friendly',
    difficulty: challenge.difficulty,
    playerAId: challenge.challenger_id,
    playerBId: challenge.recipient_id,
    now,
  });

  const created = await env.DB.prepare(
    `SELECT room_id FROM matches
     WHERE challenge_id = ? OR room_id = ?
     ORDER BY CASE WHEN challenge_id = ? THEN 0 ELSE 1 END
     LIMIT 1`,
  )
    .bind(challenge.id, roomId, challenge.id)
    .first<{ room_id: string }>();
  if (!created?.room_id) {
    throw new HttpError(500, 'Unable to create the accepted challenge room.');
  }

  await env.DB.prepare(
    `UPDATE challenges SET status = 'accepted', room_id = ?, updated_at = ? WHERE id = ?`,
  )
    .bind(created.room_id, now, challenge.id)
    .run();
  return created.room_id;
}

async function createMatchRow(
  env: Env,
  input: {
'''
replace_once("backend/social_worker/src/index.ts", helper_anchor, helper)

invitation_path = "lib/features/social/ux_challenge_invitation_screen.dart"
replace_once(
    invitation_path,
    r'''      await _economy.refresh(showLoading: false);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => PreMatchReadyScreen(roomId: roomId),
        ),
      );
    } on SocialApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('matchmaking_start_failed'));
      }
''',
    r'''      await _openRoom(roomId);
    } on SocialApiException catch (error) {
      if (accept && await _recoverAcceptedChallenge()) return;
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (accept && await _recoverAcceptedChallenge()) return;
      if (mounted) {
        setState(() => _error = context.tr('matchmaking_start_failed'));
      }
''',
)

replace_once(
    invitation_path,
    r'''    for (var attempt = 0; attempt < 5; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final active = await _social.activeMatch();
      final roomId = active?['roomId']?.toString().trim();
      if (roomId != null && roomId.isNotEmpty) return roomId;
    }
    return null;
  }

  Future<void> _openStore() async {
''',
    r'''    for (var attempt = 0; attempt < 12; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final active = await _social.activeMatch();
      final roomId = active?['roomId']?.toString().trim();
      if (roomId != null && roomId.isNotEmpty) return roomId;
    }
    return null;
  }

  Future<bool> _recoverAcceptedChallenge() async {
    for (var attempt = 0; attempt < 12; attempt++) {
      try {
        final active = await _social.activeMatch();
        final roomId = active?['roomId']?.toString().trim();
        if (roomId != null && roomId.isNotEmpty) {
          await _openRoom(roomId);
          return true;
        }
      } catch (_) {
        // The backend may still be completing or repairing the accepted room.
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<void> _openRoom(String roomId) async {
    await _economy.refresh(showLoading: false);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) => PreMatchReadyScreen(roomId: roomId),
      ),
    );
  }

  Future<void> _openStore() async {
''',
)

prematch_path = "lib/features/duel/pre_match_ready_screen.dart"
replace_once(
    prematch_path,
    r'''  bool _handedOff = false;
  bool _connecting = false;
''',
    r'''  bool _handedOff = false;
  bool _connecting = false;
  Timer? _retryTimer;
  int _connectAttempt = 0;
''',
)
replace_once(
    prematch_path,
    r'''    unawaited(_snapshotSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    if (!_handedOff) unawaited(_controller?.dispose());
''',
    r'''    _retryTimer?.cancel();
    unawaited(_snapshotSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    if (!_handedOff) unawaited(_controller?.dispose());
''',
)
replace_once(
    prematch_path,
    r'''  Future<void> _connect() async {
    if (_connecting) return;
    setState(() {
''',
    r'''  Future<void> _connect() async {
    if (_connecting || _handedOff || !mounted) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    setState(() {
''',
)
replace_once(
    prematch_path,
    r'''      setState(() {
        _controller = controller;
        _snapshotSubscription = snapshotSubscription;
        _connectionSubscription = connectionSubscription;
        _connectionState = controller.connectionState;
      });
      controller.requestSnapshot();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _connectionState = OnlineDuelConnectionState.failed;
      });
''',
    r'''      _connectAttempt = 0;
      setState(() {
        _controller = controller;
        _snapshotSubscription = snapshotSubscription;
        _connectionSubscription = connectionSubscription;
        _connectionState = controller.connectionState;
      });
      controller.requestSnapshot();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _connectionState = OnlineDuelConnectionState.failed;
      });
      _scheduleReconnect();
''',
)
replace_once(
    prematch_path,
    r'''  void _sendScreenLoaded() {
''',
    r'''  void _scheduleReconnect() {
    if (!mounted || _handedOff || _retryTimer != null) return;
    _connectAttempt++;
    final seconds = switch (_connectAttempt) {
      <= 1 => 1,
      2 => 2,
      3 => 4,
      _ => 6,
    };
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      if (mounted && !_handedOff) unawaited(_connect());
    });
  }

  void _sendScreenLoaded() {
''',
)

print("Challenge room recovery patch applied.")
