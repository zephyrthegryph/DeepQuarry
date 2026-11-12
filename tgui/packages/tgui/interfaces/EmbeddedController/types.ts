import type { BooleanLike } from 'tgui-core/react';
import type {
  AirlockConsoleSimpleActions,
  AirlockConsoleSimpleData,
} from '../generated/AirlockConsoleSimple';

/** A door set's state, as the airlock consoles send it. */
export type status = AirlockConsoleSimpleData['exterior_status'];

/** The maintenance-panel part every airlock console window with a panel sends (the airlock's ui_data()). */
export type PanelOpenData = {
  panel_open: BooleanLike;
  tags: Record<string, string | null> | null;
  frequency: number | null;
  min_freq: number | null;
  max_freq: number | null;
};

/** The panel's buttons, the same ops in every airlock console window. */
export type PanelOpenActions = Pick<
  AirlockConsoleSimpleActions,
  'edit_tag' | 'set_frequency'
>;
