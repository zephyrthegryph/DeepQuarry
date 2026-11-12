import type { CloningConsoleData } from '../generated/CloningConsole';

export type Data = CloningConsoleData;

export type modalData = NonNullable<Data['modal']>;
