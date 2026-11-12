// ── CommandContext ─────────────────────────────────────────────────────────────
// Everything a command function needs, passed from index.tsx.

import type { MutableRefObject } from 'react';
import type { GState, ScanEntry } from '../types';

export type CommandContext = {
  readonly gRef: MutableRefObject<GState>;
  readonly setG: (updater: (prev: GState) => GState) => void;
  readonly print: (text: string, color?: string) => void;
  readonly clearLines: () => void;
  readonly scanPool: MutableRefObject<ScanEntry[]>;
};
