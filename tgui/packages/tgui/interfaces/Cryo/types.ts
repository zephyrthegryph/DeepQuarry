import type { BooleanLike } from 'tgui-core/react';

export type Data = {
  isOperating: BooleanLike;
  hasOccupant: BooleanLike;
  occupant: {
    name: string;
    stat: number;
    vitality: number;
    critical: BooleanLike;
    physicalLoad: number;
    asphyxiaLoad: number;
    toxicLoad: number;
    thermalLoad: number;
    bodyTemperature: number;
  };
  cellTemperature: number;
  cellTemperatureStatus: string;
  isBeakerLoaded: BooleanLike;
  beakerLabel: string | null;
  beakerVolume: number;
};
