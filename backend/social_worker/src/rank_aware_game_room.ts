import { GameRoom as AuthoritativeGameRoom, type Env } from './index';
import {
  reconcileRankProgression,
  type RankProgressionEnv,
} from './rank_progression';
import { refreshRankPostSettlement } from './rank_post_settlement';
import { ensureRankProgressionSchema } from './rank_progression_schema';

/**
 * Production wrapper around the existing authoritative GameRoom.
 *
 * The base class still owns WebSocket state, Sudoku result authority, hidden
 * Elo/MMR and Coin escrow settlement. This wrapper only reacts after that
 * settlement is visible in D1 and reconciles the additive RP/rank-reward
 * layer. Failure here is logged and self-heals through the existing rank
 * endpoints/backfill; it can never turn a completed duel back into a failure.
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
    await super.webSocketMessage(socket, message);
    await this.reconcileRankIfAuthoritativelySettled();
  }

  override async alarm(): Promise<void> {
    await super.alarm();
    await this.reconcileRankIfAuthoritativelySettled();
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
