// ── useMarketLoop ─────────────────────────────────────────────────────────────
// Slower market-drift interval (separate from the main tick rate).

import {
  type Dispatch as ReactDispatch,
  type SetStateAction,
  useEffect,
} from 'react';

import { MARKET_TICK_MS } from '../constants';
import { computeMarketTick } from '../logic';
import type { GState, Line } from '../types';

export function useMarketLoop(
  phase: 'setup' | 'playing',
  setG: ReactDispatch<SetStateAction<GState>>,
  setLines: ReactDispatch<SetStateAction<Line[]>>,
): void {
  useEffect(() => {
    if (phase !== 'playing') return;

    const id = setInterval(() => {
      setG((prev) => {
        const { newMarket, newLastEvent, event } = computeMarketTick(
          prev.market,
          prev.lastMarketEvent,
        );

        if (event) {
          setLines((l) => [
            ...l,
            {
              text: `[MARKET] ${event.key} ${event.dir}: $${event.price}/GB`,
              color: '#ffff00',
            },
          ]);
        }

        return { ...prev, market: newMarket, lastMarketEvent: newLastEvent };
      });
    }, MARKET_TICK_MS);

    return () => clearInterval(id);
  }, [phase]); // eslint-disable-line react-hooks/exhaustive-deps
}
