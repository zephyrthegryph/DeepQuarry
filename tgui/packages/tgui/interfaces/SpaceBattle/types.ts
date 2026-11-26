import type { SpaceBattleData } from '../generated/SpaceBattle';

export type Ship = SpaceBattleData['visible_ships'][number];

export type Data = SpaceBattleData;
