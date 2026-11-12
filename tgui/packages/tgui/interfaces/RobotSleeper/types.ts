import type { RobotSleeperData } from '../generated/RobotSleeper';

export type RobotChem = NonNullable<RobotSleeperData['chems']>[number];
