import {
  createInitialDuelState as createBaseInitialDuelState,
} from './online_duel_engine';
import type { DuelVariant } from './sudoku_variant';

export type CreateInitialDuelStateInput = Parameters<
  typeof createBaseInitialDuelState
>[0];

export function createInitialDuelState(
  input: CreateInitialDuelStateInput,
): ReturnType<typeof createBaseInitialDuelState> {
  return createBaseInitialDuelState({
    ...input,
    variant: input.variant ?? variantFromRoomId(input.roomId),
  });
}

export function roomIdForVariant(
  variant: DuelVariant,
  id: string = crypto.randomUUID(),
): string {
  return `${variant}:${id}`;
}

export function variantFromRoomId(roomId: string): DuelVariant {
  return roomId.startsWith('classic16:') ? 'classic16' : 'classic9';
}
