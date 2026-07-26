export type SettlementFailpoint =
  | 'after_match_completed'
  | 'after_match_players'
  | 'after_global_rating'
  | 'after_difficulty_rating'
  | 'after_player_aggregate'
  | 'after_recent_opponents'
  | 'after_challenge_completed'
  | 'before_marker'
  | 'after_marker';

export type SettlementStore = {
  marker: boolean;
  winner: string | null;
  historyRows: Set<string>;
  globalRatings: Record<string, number>;
  difficultyRatings: Record<string, number>;
  gamesPlayed: Record<string, number>;
  wins: Record<string, number>;
  losses: Record<string, number>;
  recentOpponents: Set<string>;
  challengeCompleted: boolean;
  auditSequences: Set<number>;
};

export function createSettlementStore(): SettlementStore {
  return {
    marker: false,
    winner: null,
    historyRows: new Set<string>(),
    globalRatings: { a: 1000, b: 1000 },
    difficultyRatings: { a: 1000, b: 1000 },
    gamesPlayed: { a: 0, b: 0 },
    wins: { a: 0, b: 0 },
    losses: { a: 0, b: 0 },
    recentOpponents: new Set<string>(),
    challengeCompleted: false,
    auditSequences: new Set<number>(),
  };
}

export function settleForTest(
  store: SettlementStore,
  failpoint?: SettlementFailpoint,
): void {
  if (store.marker) return;
  store.winner = 'a';
  fail('after_match_completed', failpoint);
  store.historyRows.add('match:a');
  store.historyRows.add('match:b');
  store.auditSequences.add(1);
  fail('after_match_players', failpoint);
  store.globalRatings.a = 1020;
  store.globalRatings.b = 980;
  fail('after_global_rating', failpoint);
  store.difficultyRatings.a = 1020;
  store.difficultyRatings.b = 980;
  fail('after_difficulty_rating', failpoint);
  store.gamesPlayed.a = 1;
  store.gamesPlayed.b = 1;
  store.wins.a = 1;
  store.losses.b = 1;
  fail('after_player_aggregate', failpoint);
  store.recentOpponents.add('a:b');
  fail('after_recent_opponents', failpoint);
  store.challengeCompleted = true;
  fail('after_challenge_completed', failpoint);
  fail('before_marker', failpoint);
  store.marker = true;
  fail('after_marker', failpoint);
}

function fail(current: SettlementFailpoint, expected?: SettlementFailpoint): void {
  if (current === expected) throw new Error(`failpoint:${current}`);
}
