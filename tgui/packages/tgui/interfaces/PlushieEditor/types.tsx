import type { PlushieEditorData } from '../generated/PlushieEditor';

export type Data = PlushieEditorData;

export type Overlay = Data['overlays'][number];

export type PossibleOverlay = Data['possible_overlays'][number];

export type PlushieConfig = {
  name: string;
  base_color: string;
  icon: string;
  overlays: Overlay[];
};
