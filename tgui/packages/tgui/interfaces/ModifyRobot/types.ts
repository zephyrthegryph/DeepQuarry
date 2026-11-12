import type { BooleanLike } from 'tgui-core/react';
import type { ModifyRobotData } from '../generated/ModifyRobot';

export type Data = ModifyRobotData;

export type DropdownEntry = {
  displayText: string;
  value: string | number;
};

export type Target = NonNullable<Data['target']>;

export type Upgrade = {
  name: string;
  path: string;
  installed?: number;
};

export type Source = Data['source'];

export type Module = { name: string; ref: number; icon: string; desc: string };

export type Component = {
  name: string;
  ref: number;
  brute_damage: number;
  electronics_damage: number;
  max_damage: number;
  idle_usage: number;
  active_usage: number;
  installed: number;
  exists: BooleanLike;
};

export type PKA = {
  name: string;
  modkits: {
    name: string;
    path: string;
    costs: number;
    denied: BooleanLike;
    denied_by: string;
  }[];
  installed_modkits: { name: string; ref: number; costs: number }[];
  capacity: number;
  max_capacity: number;
};

export type Multibelt = {
  name: string;
  tools: {
    name: string;
    path: string;
  }[];
  ref: number;
  integrated_tools: { name: string; ref: number }[];
};

export type InstalledCell = {
  name: string | null;
  charge: number | null;
  maxcharge: number | null;
};

export type Cell = {
  path: string;
  charge: number;
  max_charge: number;
  charge_amount: number;
  self_charge: BooleanLike;
  max_damage: number;
};

export type Comp = {
  path: string;
  max_damage: number;
  idle_usage: number;
  active_usage: number;
} | null;

export type Access = { id: number; name: string };

export type Lookup = {
  path: string;
  selected?: string;
  active?: string;
};
