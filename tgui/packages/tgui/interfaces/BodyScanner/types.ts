import type { BooleanLike } from 'tgui-core/react';

export type Data = {
  occupied: BooleanLike;
  occupant: occupant;
};

export type DamageBand =
  | 'uninjured'
  | 'minor'
  | 'moderate'
  | 'severe'
  | 'critical';

export type DamagePanelEntry = {
  kind: string;
  label: string;
  band: DamageBand;
};

export type ScannerFinding = {
  phrase: string;
  organ: string;
  severity: DamageBand;
  trend: 'new' | 'worsening' | 'improving' | 'stable';
  stage?: string | null;
};

export type occupant = {
  name: string;
  species: string;
  stat: number;
  fakedeath: BooleanLike;
  healthBand: DamageBand;
  hasVirus: number;
  paralysisSeconds: number;
  bodyTempC: number;
  bodyTempF: number;
  hasBorer: BooleanLike;
  colourblind: BooleanLike;
  blood: { volume: number; percent: number };
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
  damagePanel: DamagePanelEntry[];
  scannerFindings: ScannerFinding[];
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
  hasBrute: BooleanLike;
  hasBurn: BooleanLike;
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
