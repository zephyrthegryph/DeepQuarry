import type { BooleanLike } from 'tgui-core/react';

export type Data = Partial<
  MultiData &
    ExploData &
    WebData & {
      shuttle_status: string | null;
      shuttle_state: string | null;
      has_docking: BooleanLike;
      docking_status: string | null;
      docking_override: BooleanLike;
      can_launch: BooleanLike;
      can_cancel: BooleanLike;
      can_force: BooleanLike;
      docking_codes: string | null;
      subtemplate: string;
    }
>;

type MultiData = {
  destination_name: string;
  can_pick: BooleanLike;
  can_cloak: BooleanLike;
  cloaked: BooleanLike;
  legit: BooleanLike;
};

type ExploData = {
  destination_name: string;
  can_pick: BooleanLike;
  fuel_usage: number;
  remaining_fuel: number;
  fuel_span: string;
  can_plot_expedition: BooleanLike;
  expedition: {
    name: string;
    objective: string;
    progress: string;
    complete: BooleanLike;
  } | null;
};

type WebData = {
  shuttle_location: string;
  future_location: string | null;
  shuttle_state: string;
  routes: { name: string; index: number; travel_time: string }[];
  has_docking: BooleanLike;
  skip_docking: BooleanLike;
  is_moving: BooleanLike;
  docking_status: string | null;
  docking_override: BooleanLike;
  is_in_transit: BooleanLike;
  travel_progress: number;
  time_left: number;
  can_cloak: BooleanLike;
  cloaked: BooleanLike;
  can_autopilot: BooleanLike;
  autopilot: BooleanLike;
  can_rename: BooleanLike;
  doors: Record<string, door>;
  sensors: Record<string, sensor>;
};

export type sensor = {
  reading: BooleanLike;
  pressure: string | null;
  n2: string | null;
  o2: string | null;
  co2: string | null;
  plasma: string | null;
  methane: string | null;
  other: string | null;
  temp: string | null;
};

export type door = { bolted: BooleanLike; open: BooleanLike };
