import type { BooleanLike } from 'tgui-core/react';

export type Data = {
  all_sensors: { name: string; alarm: BooleanLike }[];
  focus: sensor | null;
};

export type sensor = {
  name: string;
  stored: number;
  interval: number;
  attached: BooleanLike;
  history: { supply: number[]; demand: number[] };
  // Object rows are accepted during development hot reloads while an older game
  // server is still running; freshly built servers send the compact tuple form.
  areas: Array<areaPayload | area>;
};

export type areaPayload = [
  name: string,
  charge: number,
  load: string,
  charging: number,
  eqp: number,
  lgt: number,
  env: number,
];

export type area = {
  name: string;
  charge: number;
  load: string;
  charging: number;
  eqp: number;
  lgt: number;
  env: number;
};
