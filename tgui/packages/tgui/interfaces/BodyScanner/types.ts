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
