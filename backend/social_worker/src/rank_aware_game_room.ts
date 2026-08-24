import { GameRoom as AuthoritativeGameRoom, type Env } from './index';
import type { DuelState, Seat } from './online_duel';
import {
  reconcileRankProgression,
  type RankProgressionEnv,
} from './rank_progression';
import { refreshRankPostSettlement } from './rank_post_settlement';
import { ensureRankProgressionSchema } from './rank_progression_schema';

const DUEL_EMOTE_IDS = new Set([
  'smile',
  'laugh',
  'smug',
  'bored',
  'fire',
  'crown',
  'shocked',
  'respect',
]);
const DUEL_EMOTE_COOLDOWN_MS = 3_000;
type EmoteCooldownState = Partial<Record<Seat, number>>;

/**
 * Production wrapper around the existing authoritative GameRoom.
 *
 * The base class still owns WebSocket state, Sudoku result authority, hidden
 * Elo/MMR and Coin escrow settlement. This wrapper only adds two independent
 * concerns: ephemeral, rate-limited duel emotes and post-settlement RP/rank
 * reconciliation. Neither concern can mutate the authoritative Sudoku board,
 * turn revision, Elo/MMR or Coin settlement.
 */
export class GameRoom extends AuthoritativeGameRoom {
  private knownRoomId: string | null = null;
  private reconciledMatchId: string | null = null;

  constructor(
    private readonly rankState: DurableObjectState,
    private readonly rankEnv: Env,
  ) {
    super(rankState, rankEnv);
  }

  override async fetch(request: Request): Promise<Response> {
    const roomId = request.headers.get('x-sudoku-room-id')?.trim();
    if (roomId) this.knownRoomId = roomId;
    const response = await super.fetch(request);
    await this.reconcileRankIfAuthoritativelySettled();
    return response;
  }

  override async webSocketMessage(
    socket: WebSocket,
    message: string | ArrayBuffer,
  ): Promise<void> {
    if (await this.handleEmoteMessage(socket, message)) return;
    await super.webSocketMessage(socket, message);
    await this.reconcileRankIfAuthoritativelySettled();
  }

  override async alarm(): Promise<void> {
    await super.alarm();
    await this.reconcileRankIfAuthoritativelySettled();
  }

  private async handleEmoteMessage(
    socket: WebSocket,
    message: string | ArrayBuffer,
  ): Promise<boolean> {
    const text =
      typeof message === 'string' ? message : new TextDecoder().decode(message);
    if (text.length > 4096) return false;

    let parsed: {
      v?: unknown;
      type?: unknown;
      payload?: { emoteId?: unknown } | null;
    };
    try {
      parsed = JSON.parse(text) as typeof parsed;
    } catch {
      return false;
    }
    if (parsed.v !== 1 || parsed.type !== 'emote') return false;

    const now = Date.now();
    const duel = await this.rankState.storage.get<DuelState>('duelState');
    const [playerId] = this.rankState.getTags(socket);
    const seat = this.emoteSeatForPlayer(duel, playerId);
    if (!duel || !seat) {
      this.sendEmoteEvent(socket, {
        type: 'emote_rejected',
        roomId: duel?.roomId ?? 'room',
        revision: duel?.revision ?? 0,
        seat: seat ?? 'A',
        now,
        payload: { reason: 'room_not_initialized' },
      });
      return true;
    }

    const roomId = duel.roomId;
    const revision = duel.revision;
    const emoteId =
      typeof parsed.payload?.emoteId === 'string'
        ? parsed.payload.emoteId.trim()
        : '';

    if (duel.status !== 'active') {
      this.sendEmoteEvent(socket, {
        type: 'emote_rejected',
        roomId,
        revision,
        seat,
        now,
        payload: { reason: 'game_not_active' },
      });
      return true;
    }
    if (!DUEL_EMOTE_IDS.has(emoteId)) {
      this.sendEmoteEvent(socket, {
        type: 'emote_rejected',
        roomId,
        revision,
        seat,
        now,
        payload: { reason: 'invalid_emote' },
      });
      return true;
    }

    const cooldowns =
      (await this.rankState.storage.get<EmoteCooldownState>(
        'duelEmoteCooldowns',
      )) ?? {};
    const lastSentAt = cooldowns[seat] ?? 0;
    if (now - lastSentAt < DUEL_EMOTE_COOLDOWN_MS) {
      this.sendEmoteEvent(socket, {
        type: 'emote_rejected',
        roomId,
        revision,
        seat,
        now,
        payload: { reason: 'emote_cooldown' },
      });
      return true;
    }

    cooldowns[seat] = now;
    await this.rankState.storage.put('duelEmoteCooldowns', cooldowns);

    // A room only accepts sockets belonging to its two authenticated players.
    // Relay to every other accepted socket instead of requiring the recipient
    // tag to map back to a seat. That keeps delivery working across Durable
    // Object hibernation/reconnects even if a recovered socket has incomplete
    // tag metadata. We still exclude every socket tagged as the sender so the
    // sender never receives its own emote presentation event.
    let recipientCount = 0;
    for (const target of this.rankState.getWebSockets()) {
      const [targetPlayerId] = this.rankState.getTags(target);
      if (target === socket || (targetPlayerId && targetPlayerId === playerId)) {
        continue;
      }
      this.sendEmoteEvent(target, {
        type: 'emote',
        roomId,
        revision,
        seat,
        now,
        payload: { emoteId },
      });
      recipientCount++;
    }

    // Silent protocol acknowledgement. The Flutter UI deliberately does not
    // render this as a banner/snackbar; it exists so delivery can be diagnosed
    // without duplicating the emote on the sender's screen.
    this.sendEmoteEvent(socket, {
      type: 'emote_ack',
      roomId,
      revision,
      seat,
      now,
      payload: { emoteId, recipientCount },
    });
    return true;
  }

  private emoteSeatForPlayer(
    duel: DuelState | undefined,
    playerId: string | undefined,
  ): Seat | null {
    if (!duel || !playerId) return null;
    if (duel.playerA.player.id === playerId) return 'A';
    if (duel.playerB.player.id === playerId) return 'B';
    return null;
  }

  private sendEmoteEvent(
    socket: WebSocket,
    input: {
      type: 'emote' | 'emote_ack' | 'emote_rejected';
      roomId: string;
      revision: number;
      seat: Seat;
      now: number;
      payload: {
        emoteId?: string;
        reason?: string;
        recipientCount?: number;
      };
    },
  ): void {
    try {
      socket.send(
        JSON.stringify({
          v: 1,
          type: input.type,
          eventId: `${input.roomId}:${input.revision}:${input.type}:${input.seat}:${input.now}`,
          revision: input.revision,
          serverTime: input.now,
          payload: { seat: input.seat, ...input.payload },
        }),
      );
    } catch {
      // Closed sockets are removed by the Durable Object hibernation runtime.
    }
  }

  private async reconcileRankIfAuthoritativelySettled(): Promise<void> {
    try {
      const roomId = await this.resolveRoomId();
      if (!roomId) return;
      const match = await this.rankEnv.DB.prepare(
        `SELECT id, mode, rated, status, started_at, rating_settled_at,
                player_a_id, player_b_id
         FROM matches
         WHERE room_id = ?
         LIMIT 1`,
      )
        .bind(roomId)
        .first<{
          id: string;
          mode: string;
          rated: number;
          status: string;
          started_at: string | null;
          rating_settled_at: string | null;
          player_a_id: string;
          player_b_id: string;
        }>();
      if (!match || this.reconciledMatchId === match.id) return;
      if (
        match.mode !== 'ranked' ||
        Number(match.rated) !== 1 ||
        !match.started_at ||
        !match.rating_settled_at ||
        !['completed', 'forfeited', 'abandoned'].includes(match.status)
      ) {
        return;
      }

      const env = this.rankEnv as RankProgressionEnv;
      await ensureRankProgressionSchema(env);
      for (const playerId of [match.player_a_id, match.player_b_id]) {
        await reconcileRankProgression(env, playerId);
        await refreshRankPostSettlement(env, playerId);
      }
      this.reconciledMatchId = match.id;
    } catch (error) {
      console.error('rank_post_match_reconciliation_failed', {
        roomId: this.knownRoomId,
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  private async resolveRoomId(): Promise<string | null> {
    if (this.knownRoomId) return this.knownRoomId;
    const stored = await this.rankState.storage.get<{ roomId?: unknown }>(
      'duelState',
    );
    const roomId = String(stored?.roomId ?? '').trim();
    if (!roomId) return null;
    this.knownRoomId = roomId;
    return roomId;
  }
}
