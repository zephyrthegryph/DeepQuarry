import type { GhostSpawnData } from '../generated/GhostSpawn';

export type Data = GhostSpawnData;

export type PodData = NonNullable<Data['all_ghost_pods']>[number];

export type VoreSpawnData = NonNullable<Data['all_vore_spawns']>[string];

export type DropdownEntry = {
  displayText: string;
  value: string;
};

export type GhostJoinData = NonNullable<Data['all_ghost_join_options']>;

export type MouseData = GhostJoinData['mouse_data'];

export type DroneData = GhostJoinData['drone_data'];

export type VRData = GhostJoinData['vr_data'];

export type describeReturnData = {
  text: string;
  state: boolean;
  name?: string;
  action?: string;
};
