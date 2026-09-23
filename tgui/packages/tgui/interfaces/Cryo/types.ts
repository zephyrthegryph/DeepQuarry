import type { BooleanLike } from 'tgui-core/react';

import type { Diagnosis } from '../common/Diagnosis';

export type Data = {
  isOperating: BooleanLike;
  hasOccupant: BooleanLike;
  occupant: {
    name: string;
    stat: number;
    vitality: number;
    critical: BooleanLike;
    diagnosis: Diagnosis;
    bodyTemperature: number;
  };
  cellTemperature: number;
  cellTemperatureStatus: string;
  isBeakerLoaded: BooleanLike;
  beakerLabel: string | null;
  beakerVolume: number;
};
