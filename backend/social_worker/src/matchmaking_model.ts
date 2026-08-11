export type QueueTicket = {
  playerId: string;
  difficulty: string;
  rating: number;
  joinedAt: number;
};

export type QueueDecision =
  | { status: 'queued'; ticket: QueueTicket }
  | { status: 'matched'; playerA: QueueTicket; playerB: QueueTicket; roomId: string };

export function joinQueueForTest(input: {
  tickets: QueueTicket[];
  playerId: string;
  difficulty: string;
  rating: number;
  now: number;
  activePlayers?: Set<string>;
  blockedPairs?: Set<string>;
}): QueueDecision {
  if (input.activePlayers?.has(input.playerId)) {
    throw new Error('active_match_exists');
  }
  const existing = input.tickets.find((ticket) => ticket.playerId === input.playerId);
  if (existing) {
    existing.difficulty = input.difficulty;
    existing.rating = input.rating;
    return { status: 'queued', ticket: existing };
  }
  const opponent = input.tickets
    .filter((ticket) => ticket.difficulty === input.difficulty)
    .filter((ticket) => ticket.playerId !== input.playerId)
    .filter((ticket) => !input.blockedPairs?.has(pairKey(ticket.playerId, input.playerId)))
    .sort((a, b) => Math.abs(a.rating - input.rating) - Math.abs(b.rating - input.rating) || a.joinedAt - b.joinedAt)[0];
  const ticket = {
    playerId: input.playerId,
    difficulty: input.difficulty,
    rating: input.rating,
    joinedAt: input.now,
  };
  if (!opponent) {
    input.tickets.push(ticket);
    return { status: 'queued', ticket };
  }
  input.tickets.splice(input.tickets.indexOf(opponent), 1);
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
