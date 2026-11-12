import type { RpgDiceData } from '../generated/RpgDice';

export type Data = RpgDiceData;

export type Result = RpgDiceData['last_rolls'][number]['results'][number];
