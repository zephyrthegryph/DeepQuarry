// ── Hooks barrel ──────────────────────────────────────────────────────────────
// Composes the tick loop and market loop into a single hook for index.tsx.

import type { Dispatch as ReactDispatch, SetStateAction } from 'react';

import type { GState, Line } from '../types';
import { useMarketLoop } from './useMarketLoop';
import { useTickLoop } from './useTickLoop';

export function useGameLoop(
  phase: 'setup' | 'playing',
  gRef: React.RefObject<GState>,
  setG: ReactDispatch<SetStateAction<GState>>,
  setLines: ReactDispatch<SetStateAction<Line[]>>,
): void {
  useTickLoop(phase, gRef, setG, setLines);
  useMarketLoop(phase, setG, setLines);
}
