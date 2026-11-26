import type { ChemMasterData } from '../generated/ChemMaster';

export type Data = ChemMasterData;

export type reagent = ChemMasterData['beaker_reagents'][number];

export type modalData = {
  id: string;
  text: string;
  args: {
    analysis: {
      idx: string;
      name: string;
      desc: string;
      blood_type: string | null;
      blood_dna: string | null;
    };
    beaker: number;
  };
  type: string;
};
