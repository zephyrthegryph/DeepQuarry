import type { BooleanLike } from 'tgui-core/react';

import type { Diagnosis } from '../common/Diagnosis';

export type Data = {
  hasOccupant: BooleanLike;
  occupant: occupant;
  verbose: BooleanLike;
  spo2Alarm: number;
  choice: BooleanLike;
  health: BooleanLike;
  crit: BooleanLike;
  healthAlarm: number;
  spo2: BooleanLike;
};

export type occupant = {
  name: string;
  stat: number;
  vitality: number;
  paralysis: number;
  diagnosis: Diagnosis;
  bloodType: string | undefined;
  surgery: { name: string; currentStage: string; nextSteps: string[] }[] | null;
};
