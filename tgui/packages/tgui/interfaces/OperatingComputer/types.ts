import type { OperatingComputerData } from '../generated/OperatingComputer';

export type Data = OperatingComputerData;

export type occupant = NonNullable<Data['occupant']>;
