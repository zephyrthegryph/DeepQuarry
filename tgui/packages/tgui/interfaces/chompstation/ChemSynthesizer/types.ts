import type { ChemSynthesizerData } from '../../generated/ChemSynthesizer';

export type Data = ChemSynthesizerData;

export type reagent = ChemSynthesizerData['rxn_vessel'][number];

export type modalData = {
  id: string;
  text: string;
  // biome-ignore lint/complexity/noBannedTypes: In this case we got any type of Object
  args: {};
  type: string;
};
