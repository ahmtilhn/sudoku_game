import { describe, expect, it, vi } from "vitest";

import { GameRoom } from "../src/rank_aware_game_room";
import { createInitialDuelState } from "../src/online_duel";

type SentFrame = Record<string, unknown> & {
  type: string;
  payload: Record<string, unknown>;
};

class FakeSocket {
  readonly sent: SentFrame[] = [];
  readyState = 1;

  constructor(readonly playerId: string) {}

  send(frame: string): void {
    this.sent.push(JSON.parse(frame) as SentFrame);
  }

  close(): void {
    this.readyState = 3;
  }
}

class FakeStorage {
  private readonly values = new Map<string, unknown>();

  async get<T>(key: string): Promise<T | undefined> {
    return this.values.get(key) as T | undefined;
  }

  async put(key: string, value: unknown): Promise<void> {
    this.values.set(key, value);
  }
}

class FakeDurableObjectState {
  readonly storage = new FakeStorage();
  private readonly sockets: FakeSocket[] = [];

  blockConcurrencyWhile(callback: () => Promise<void>): void {
    void callback();
  }

  accept(socket: FakeSocket): void {
    this.sockets.push(socket);
  }

  getTags(socket: FakeSocket): string[] {
    return [socket.playerId];
  }

  getWebSockets(tag?: string): FakeSocket[] {
    return this.sockets.filter(
      (socket) => socket.readyState === 1 && (!tag || socket.playerId === tag),
    );
  }
}

describe("runtime online duel emote relay", () => {
  it("delivers an active emote only to the opponent and rate-limits repeats", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(10_000);

    const state = new FakeDurableObjectState();
    const room = new GameRoom(
      state as unknown as DurableObjectState,
      { DB: {} } as never,
    );
    const playerA = new FakeSocket("player-a");
    const playerB = new FakeSocket("player-b");
    state.accept(playerA);
    state.accept(playerB);
    const duel = createInitialDuelState({
      roomId: "room-emote",
      matchId: "match-emote",
      challengeId: "challenge-emote",
      mode: "friendly",
      difficulty: "easy",
      playerA: {
        id: "player-a",
        publicId: "PA",
        username: "alice",
        displayName: "Alice",
        avatarKey: "default",
      },
      playerB: {
        id: "player-b",
        publicId: "PB",
        username: "bob",
        displayName: "Bob",
        avatarKey: "default",
      },
      now: 9_000,
      randomBytes: new Uint8Array([
        7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6,
      ]),
    });
    duel.status = "active";
    await state.storage.put("duelState", duel);

    await room.webSocketMessage(
      playerA as unknown as WebSocket,
      JSON.stringify({ v: 1, type: "emote", payload: { emoteId: "fire" } }),
    );

    expect(playerB.sent).toHaveLength(1);
    expect(playerB.sent[0]).toMatchObject({
      type: "emote",
      revision: duel.revision,
      payload: { seat: "A", emoteId: "fire" },
    });
    expect(playerA.sent).toHaveLength(1);
    expect(playerA.sent[0]).toMatchObject({
      type: "emote_ack",
      payload: { seat: "A", emoteId: "fire", recipientCount: 1 },
    });

    await room.webSocketMessage(
      playerA as unknown as WebSocket,
      JSON.stringify({ v: 1, type: "emote", payload: { emoteId: "crown" } }),
    );

    expect(playerB.sent).toHaveLength(1);
    expect(playerA.sent.at(-1)).toMatchObject({
      type: "emote_rejected",
      payload: { seat: "A", reason: "emote_cooldown" },
    });

    vi.useRealTimers();
  });
});
