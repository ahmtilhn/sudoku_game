export type QueueTicket = {
  playerId: string;
  difficulty: string;
  rating: number;
  joinedAt: number;
  variant?: string;
};

export type QueueDecision =
  | { status: 'queued'; ticket: QueueTicket }
  | { status: 'matched'; playerA: QueueTicket; playerB: QueueTicket; roomId: string };

export const MATCHMAKING_UNBOUNDED_RATING_DELTA = 10_000;

export function matchmakingRatingDeltaForWaitMs(waitMs: number): number {
  const safeWaitMs = Math.max(0, Number.isFinite(waitMs) ? waitMs : 0);
  if (safeWaitMs < 5_000) return 150;
  if (safeWaitMs < 10_000) return 300;
  if (safeWaitMs < 15_000) return 500;
  if (safeWaitMs < 20_000) return 750;
  return MATCHMAKING_UNBOUNDED_RATING_DELTA;
}

export function joinQueueForTest(input: {
  tickets: QueueTicket[];
  playerId: string;
  difficulty: string;
  rating: number;
  now: number;
  variant?: string;
  activePlayers?: Set<string>;
  blockedPairs?: Set<string>;
}): QueueDecision {
  if (input.activePlayers?.has(input.playerId)) {
    throw new Error('active_match_exists');
  }

  const variant = input.variant ?? 'classic9';
  const existing = input.tickets.find((ticket) => ticket.playerId === input.playerId);
  const ticket: QueueTicket = existing ?? {
    playerId: input.playerId,
    difficulty: input.difficulty,
    rating: input.rating,
    joinedAt: input.now,
    variant,
  };

  if (existing) {
    const variantChanged = (existing.variant ?? 'classic9') !== variant;
    const difficultyChanged = existing.difficulty !== input.difficulty;
    existing.difficulty = input.difficulty;
    existing.rating = input.rating;
    existing.variant = variant;
    if (variantChanged || difficultyChanged) existing.joinedAt = input.now;
  }

  const ownWaitMs = Math.max(0, input.now - ticket.joinedAt);
  const ownRatingDelta = matchmakingRatingDeltaForWaitMs(ownWaitMs);
  const opponent = input.tickets
    .filter((candidate) => candidate.playerId !== input.playerId)
    .filter((candidate) => (candidate.variant ?? 'classic9') === variant)
    .filter(
      (candidate) =>
        !input.blockedPairs?.has(pairKey(candidate.playerId, input.playerId)),
    )
    .filter((candidate) => {
      const opponentWaitMs = Math.max(0, input.now - candidate.joinedAt);
      const opponentRatingDelta = matchmakingRatingDeltaForWaitMs(opponentWaitMs);
      const pairRatingDelta = Math.abs(candidate.rating - input.rating);
      return pairRatingDelta <= Math.min(ownRatingDelta, opponentRatingDelta);
    })
    .sort(
      (a, b) =>
        Number(b.difficulty === input.difficulty) -
          Number(a.difficulty === input.difficulty) ||
        Math.abs(a.rating - input.rating) - Math.abs(b.rating - input.rating) ||
        a.joinedAt - b.joinedAt,
    )[0];

  if (!opponent) {
    if (!existing) input.tickets.push(ticket);
    return { status: 'queued', ticket };
  }

  input.tickets.splice(input.tickets.indexOf(opponent), 1);
  if (existing) input.tickets.splice(input.tickets.indexOf(existing), 1);
  return {
    status: 'matched',
    playerA: opponent,
    playerB: ticket,
    roomId: pairKey(opponent.playerId, ticket.playerId),
  };
}

export function pairKey(a: string, b: string): string {
  return a < b ? `${a}:${b}` : `${b}:${a}`;
}
