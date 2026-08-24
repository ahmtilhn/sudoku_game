import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const wrapper = readFileSync(
  new URL('../src/rank_aware_game_room.ts', import.meta.url),
  'utf8',
);
const entry = readFileSync(
  new URL('../src/entry_v2.ts', import.meta.url),
  'utf8',
);

describe('rank-aware production GameRoom', () => {
  it('wraps rather than replaces authoritative duel settlement', () => {
    expect(wrapper).toContain("GameRoom as AuthoritativeGameRoom");
    expect(wrapper).toContain('extends AuthoritativeGameRoom');
    expect(wrapper).toContain('await super.webSocketMessage(socket, message)');
    expect(wrapper).toContain('await super.alarm()');
  });

  it('intercepts only emotes before delegating normal duel messages', () => {
    expect(wrapper).toContain("parsed.type !== 'emote'");
    expect(wrapper).toContain(
      'if (await this.handleEmoteMessage(socket, message)) return;',
    );
    expect(wrapper).toContain('await super.webSocketMessage(socket, message)');
  });

  it('keeps emotes ephemeral, whitelisted and server rate limited', () => {
    expect(wrapper).toContain('const DUEL_EMOTE_IDS = new Set([');
    expect(wrapper).toContain('const DUEL_EMOTE_COOLDOWN_MS = 3_000');
    expect(wrapper).toContain("duel.status !== 'active'");
    expect(wrapper).toContain("'invalid_emote'");
    expect(wrapper).toContain("'emote_cooldown'");
    expect(wrapper).toContain("'duelEmoteCooldowns'");
    expect(wrapper).toContain('this.rankState.getWebSockets()');
  });

  it('delivers accepted emotes only to the opponent socket', () => {
    expect(wrapper).toContain('const [targetPlayerId] = this.rankState.getTags(target)');
    expect(wrapper).toContain(
      'const targetSeat = this.emoteSeatForPlayer(duel, targetPlayerId)',
    );
    expect(wrapper).toContain('if (!targetSeat || targetSeat === seat) continue;');
  });

  it('only reconciles after an authoritative rated ranked settlement exists', () => {
    expect(wrapper).toContain("match.mode !== 'ranked'");
    expect(wrapper).toContain('Number(match.rated) !== 1');
    expect(wrapper).toContain('!match.rating_settled_at');
    expect(wrapper).toContain("['completed', 'forfeited', 'abandoned'].includes(match.status)");
  });

  it('reconciles both visible RP and post-settlement rank rewards for both players', () => {
    expect(wrapper).toContain('match.player_a_id, match.player_b_id');
    expect(wrapper).toContain('await reconcileRankProgression(env, playerId)');
    expect(wrapper).toContain('await refreshRankPostSettlement(env, playerId)');
    expect(wrapper).toContain('await ensureRankProgressionSchema(env)');
  });

  it('keeps rank reconciliation failure isolated from the completed duel', () => {
    expect(wrapper).toContain("console.error('rank_post_match_reconciliation_failed'");
    expect(wrapper).not.toContain('throw error');
  });

  it('exports the rank-aware GameRoom from the production entrypoint', () => {
    expect(entry).toContain("import { GameRoom } from './rank_aware_game_room'");
    expect(entry).toContain('export { GameRoom, MatchmakingQueue }');
  });
});
