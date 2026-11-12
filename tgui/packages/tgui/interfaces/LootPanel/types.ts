import type { LootPanelData } from '../generated/LootPanel';

export type SearchItem = LootPanelData['contents'][number];

export type SearchGroup = {
  amount: number;
  item: SearchItem;
};
