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

export type BackendState<TData> = ExtractAtomValue<typeof backendStateAtom> & {
  act: typeof sendAct;
  data: TData;
};
