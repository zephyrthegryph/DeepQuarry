import type { BooleanLike } from 'tgui-core/react';

import type { Diagnosis, DiagnosisBand } from '../common/Diagnosis';

export type Data = {
  occupied: BooleanLike;
  occupant: occupant;
};

export type DamageBand = DiagnosisBand;

export type occupant = {
  name: string;
  species: string;
  stat: number;
  fakedeath: BooleanLike;
  healthBand: DamageBand;
  hasVirus: number;
  paralysisSeconds: number;
  hasBorer: BooleanLike;
  colourblind: BooleanLike;
  reagents: reagent[];
  ingested: reagent[];
  extOrgan: externalOrgan[];
  intOrgan: internalOrgan[];
  blind: BooleanLike;
  nearsighted: BooleanLike;
  brokenspine: BooleanLike;
  livingPrey: number;
  humanPrey: number;
  objectPrey: number;
  weight: number;
  husked: BooleanLike;
  hasWithdrawl: BooleanLike;
  hasAllergens: BooleanLike;
  allergens: string[] | null;
  diagnosis: Diagnosis;
  worstFinding: DamageBand;
};

type reagent = { name: string; amount: number; overdose: BooleanLike };

export type internalOrgan = {
  name: string;
  desc?: string | null;
  germ_level?: number;
  injuryBand?: DamageBand;
  robotic: BooleanLike;
  dead: BooleanLike;
  inflamed: BooleanLike;
  missing: BooleanLike;
};

export type externalOrgan = {
  name: string;
  open: BooleanLike;
  germ_level: number;
  injuryBand: DamageBand;
  implants: { name: string; known: BooleanLike }[];
  implants_len: number;
  status: {
    destroyed: BooleanLike;
    broken: string;
    robotic: BooleanLike;
    splinted: BooleanLike;
    bleeding: BooleanLike;
    dead: BooleanLike;
  };
  lungRuptured: BooleanLike;
  internalBleeding: BooleanLike;
};
