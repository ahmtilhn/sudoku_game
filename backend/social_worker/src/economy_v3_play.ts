import {
  economyV3State,
  EconomyV3Error,
  insertCoinEvent,
  type EconomyV3Env,
} from './economy_v3_common';
import { CAREER_REWARDS } from './economy_v3_policy';

export type PlayDifficulty = keyof typeof CAREER_REWARDS;

export function normalizePlayDifficulty(value: unknown): PlayDifficulty {
  const difficulty = String(value ?? '').trim().toLowerCase();
  if (!(difficulty in CAREER_REWARDS)) {
    throw new EconomyV3Error(400, 'Invalid Sudoku difficulty.', 'invalid_difficulty');
  }
  return difficulty as PlayDifficulty;
}

export async function claimPlayReward(
  env: EconomyV3Env,
  playerId: string,
  input: {
    puzzleId: string;
    difficulty: PlayDifficulty;
    variant: 'classic9' | 'classic16';
  },
): Promise<Record<string, unknown>> {
  const expectedPrefix =
    input.variant === 'classic16'
      ? `classic16-${input.difficulty}-`
      : `generated-${input.difficulty}-`;
  if (!input.puzzleId.startsWith(expectedPrefix)) {
    throw new EconomyV3Error(
      400,
      'The Quick Play puzzle does not match the selected mode.',
      'invalid_play_puzzle',
    );
  }

  const amount = CAREER_REWARDS[input.difficulty];
  const inserted = await insertCoinEvent(env, {
    playerId,
    source: 'play_completion',
    referenceId: `${input.variant}:${input.puzzleId}`,
    amount,
    ledgerReason: 'achievement_reward',
    metadata: {
      mode: 'quick_play',
      variant: input.variant,
      difficulty: input.difficulty,
      puzzleId: input.puzzleId,
      rewardPolicy: 'difficulty_completion',
    },
  });

  return {
    granted: inserted,
    amount: inserted ? amount : 0,
    replay: !inserted,
    difficulty: input.difficulty,
    variant: input.variant,
    puzzleId: input.puzzleId,
    ...(await economyV3State(env, playerId)),
  };
}
