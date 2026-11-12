import type { BooleanLike } from 'tgui-core/react';

/** What the colour-matrix prompt window sends beyond the machine's own data (code/library/ui/tgui_input/matrix.dm). */
export type ColorMatePromptData = {
  message?: string;
  title?: string;
  matrix_only?: BooleanLike;
};
export type ColorPair = { input: string; output: string };
export type SelectedId = { id: number | null; type: 'input' | 'output' | null };

export type ColorUpdate = (hex: string, mode?: string, index?: number) => void;
