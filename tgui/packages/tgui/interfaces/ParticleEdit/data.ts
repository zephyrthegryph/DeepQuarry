import type { ParticleEditData } from '../generated/ParticleEdit';

export const RandTypes = [
  'UNIFORM_RAND',
  'NORMAL_RAND',
  'LINEAR_RAND',
  'SQUARE_RAND',
];
export const RandToNumber = {
  UNIFORM_RAND: 1,
  NORMAL_RAND: 2,
  LINEAR_RAND: 3,
  SQUARE_RAND: 4,
};

export const P_DATA_GENERATOR = 'generator';
export const P_DATA_ICON_ADD = 'icon_add';
export const P_DATA_ICON_REMOVE = 'icon_remove';
export const P_DATA_ICON_WEIGHT = 'icon_edit';
export const P_DATA_GRADIENT = 'gradient';

export const MatrixTypes = [
  'Simple Matrix',
  'Complex Matrix',
  'Projection Matrix',
];

export const SpaceTypes = [
  'COLORSPACE_RGB',
  'COLORSPACE_HSV',
  'COLORSPACE_HSL',
  'COLORSPACE_HCY',
];
export const SpaceToNum = {
  COLORSPACE_RGB: 0,
  COLORSPACE_HSV: 1,
  COLORSPACE_HSL: 2,
  COLORSPACE_HCY: 3,
};

export const GeneratorTypes = [
  'num',
  'vector',
  'box',
  'color',
  'circle',
  'sphere',
  'square',
  'cube',
];

export const GeneratorTypesNoVectors = [
  'num',
  'color',
  'circle',
  'sphere',
  'square',
  'cube',
];

export type ParticleUIData = ParticleEditData;

export type ParticleData = ParticleEditData['particle_data'];

export type EntryFloatProps = {
  name: string;
  var_name: string;
  float: number;
};

export type EntryCoordProps = {
  name: string;
  var_name: string;
  coord?: number | number[];
};

export type EntryGradientProps = {
  name: string;
  var_name: string;
  gradient?: (string | number | { space: number })[];
};

export type EntryTransformProps = {
  name: string;
  var_name: string;
  transform?: number[] | null;
};

export type EntryIconStateProps = {
  name: string;
  var_name: string;
  icon_state?: string | { [key: string]: number } | null;
};

export type FloatGeneratorProps = {
  name: string;
  var_name: string;
  float?: number | string[];
};

export type FloatGeneratorColorProps = {
  name: string;
  var_name: string;
  float?: number | string | string[];
};

export type GeneratorProps = {
  var_name: string;
  generator?: string[];
  allow_vectors?: boolean;
};

export type EntryGeneratorNumbersListProps = {
  name: string;
  var_name: string;
  allow_z: boolean;
  input?: number | number[] | string[];
};
