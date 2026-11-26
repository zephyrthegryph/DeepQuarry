import type { BiogeneratorData } from '../generated/Biogenerator';

type Item = BiogeneratorData['items'][string][string];

// affordable is worked out by the window from the points.
export type Sortable = Item & {
  affordable: number;
};

export type Data = Omit<BiogeneratorData, 'items'> & {
  items: Record<string, Record<string, Sortable>>;
};
