import type { AppearanceChangerData } from '../generated/AppearanceChanger';

export type Data = AppearanceChangerData;

export type Styles = Data['ear_styles'][number];

export type BodyStyle = Data['hair_styles'][number];

export type Species = Data['species'][number];
