import type { ModifyRobotData } from '../generated/ModifyRobot';

export type Data = ModifyRobotData;

export type DropdownEntry = {
  displayText: string;
  value: string | number;
};

export type Target = NonNullable<Data['target']>;

export type Upgrade = Target['whitelisted_upgrades'][number] & {
  installed?: number;
};

export type Source = Data['source'];

export type Module = Target['modules'][number];

export type Component = Target['components'][number];

export type PKA = NonNullable<Target['pka']>;

export type Multibelt = Target['multibelt'][number];

export type InstalledCell = NonNullable<Data['cell']>;

export type Cell = NonNullable<Data['cell_options']>[string];

export type Comp = NonNullable<Data['camera_options']>[string];

export type Access = Target['active_access'][number];

export type Lookup = {
  path: string;
  selected?: string;
  active?: string;
};
