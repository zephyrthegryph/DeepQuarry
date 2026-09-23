import type { BooleanLike } from 'tgui-core/react';

export type Data = {
  isAI: BooleanLike;
  map_levels: number[];
  crewmembers: Crewmember[];
};

export type CrewCondition =
  | 'dead'
  | 'critical'
  | 'uninjured'
  | 'minor'
  | 'moderate'
  | 'severe';

export type Crewmember = {
  sensor_type: number;
  name: string;
  rank: string;
  assignment: string;
  dead: BooleanLike;
  stat?: number;
  condition?: CrewCondition;
  vitality?: number;
  heartRate?: number | null;
  oxygenation?: number | null;
  temperature?: number | null;
  area: string;
  x: number;
  y: number;
  realZ: number;
  z: number;
  ref: string;
};
