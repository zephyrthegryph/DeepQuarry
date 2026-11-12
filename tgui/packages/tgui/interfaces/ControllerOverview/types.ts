import type { ControllerOverviewData } from '../generated/ControllerOverview';

export type ControllerData = ControllerOverviewData;
export type SubsystemData = ControllerData['subsystems'][number];

export enum SortType {
  Name,
  Cost,
  InitOrder,
  LastFire,
  NextFire,
  TickUsage,
  TickOverrun,
}
