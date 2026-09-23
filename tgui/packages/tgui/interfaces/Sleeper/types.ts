import type { BooleanLike } from 'tgui-core/react';

import type { Diagnosis } from '../common/Diagnosis';

export type Data = {
  amounts: number[];
  hasOccupant: BooleanLike;
  occupant: occupant;
  maxchem: number;
  dialysis: BooleanLike;
  stomachpumping: BooleanLike;
  auto_eject_dead: BooleanLike;
  isBeakerLoaded: BooleanLike;
  beakerMaxSpace: number;
  beakerFreeSpace: number;
  stasis: string;
  chemicals: chemical[];
};

type chemical = {
  title: string;
  id: number;
  commands: { chemical: number };
  occ_amount: number;
  pretty_amount: number;
  injectable: BooleanLike;
  overdosing: BooleanLike;
  od_warning: BooleanLike;
};

export type occupant = {
  name: string;
  stat: number;
  vitality: number;
  critical: BooleanLike;
  diagnosis: Diagnosis;
  paralysis: number;
  hasBlood: BooleanLike;
  bodyTemperature: number;
  maxTemp: number;
  temperatureSuitability: number;
  btCelsius: number;
  btFaren: number;
  pulse: number | undefined;
  bloodLevel: number | undefined;
  bloodMax: number | undefined;
  bloodPercent: number | undefined;
  bloodType: string | undefined;
};
