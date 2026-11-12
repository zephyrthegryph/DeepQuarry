import type { ExtractAtomValue } from 'jotai';
import type { sendAct } from 'tgui/events/act';
import type { backendStateAtom } from './store';

type BinaryIO = 0 | 1;

type Client = {
  address: string;
  ckey: string;
  computer_id: string;
  profiling?: BinaryIO;
};

type IFace = {
  layout: string;
  name: string;
};

type TguiWindow = {
  fancy: BinaryIO;
  key: string;
  locked: BinaryIO;
  scale: BinaryIO;
  size: [number, number];
  prewarmed?: BinaryIO;
  generation?: number;
  native_shell?: BinaryIO;
  default_geometry?: { width: number; height: number };
  geometry_preapplied?: BinaryIO;
  preapplied_geometry?: { pos?: string; size?: string };
  /** Framed by the stat panel's window dock (no own titlebar; the panel shows it). */
  docked?: BinaryIO;
  /** May dock (a pooled window that is not a modal prompt). */
  dockable?: BinaryIO;
  /** Floated by a drag out of the dock: the screen point ("x,y", physical px) to open under, once. */
  float_at?: string | null;
  /** Docked: whether the column offers float for it (never for the stat panel). */
  floatable?: boolean;
  /** Docked: whether an entry holding it can fold to its header (never the stat panel). */
  collapsible?: boolean;
  /** Docked: whether the column offers close and float buttons and a drag out for it (never the stat panel or the chat). */
  closable?: boolean;
};

type User = {
  name: string;
  observer: number;
};

type MapData = { maxx: number; maxy: number };

export type Config = {
  chunk_base_url?: string;
  startup_profile?: Record<string, unknown>;
  client: Client;
  interface: IFace;
  refreshing: BinaryIO;
  status: number;
  map: string;
  mapZLevel: number;
  mapInfo: MapData;
  title: string;
  user: User;
  window: TguiWindow;
};

export type DebugState = {
  debugLayout: boolean;
  kitchenSink: boolean;
};

/** Window actions the engine answers for every window (code/library/ui/tgui/external.dm, code/engine/parts/inputs.dm). */
export type EngineActions = {
  change_ui_state: { new_state?: string };
  modal_open: { id?: string };
  modal_answer: { id?: string; answer?: string };
  modal_close: { id?: string };
};

type ActKey<TActions> = keyof (TActions & EngineActions) & string;

/**
 * act() typed by a window's generated actions (interfaces/generated/<Window>.d.ts, `<Window>Actions`): a literal action must be one the
 * window's ui_act() ops answer and its payload keys the op's arg() names. An action held in a string variable is not checked. Without a
 * TActions type, act() takes any action.
 */
export type TypedAct<TActions> = [TActions] extends [undefined]
  ? typeof sendAct
  : unknown extends TActions // ReturnType<typeof useBackend> instantiates TActions as unknown
    ? typeof sendAct
    : <K extends string>(
        action: string extends K ? K : K & ActKey<TActions>,
        payload?: string extends K
          ? Record<string, unknown>
          : Partial<(TActions & EngineActions)[K & ActKey<TActions>]>,
      ) => void;

export type BackendState<TData, TActions = undefined> = ExtractAtomValue<
  typeof backendStateAtom
> & {
  act: TypedAct<TActions>;
  data: TData;
};
