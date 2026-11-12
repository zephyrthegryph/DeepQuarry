import type { ResleevingConsoleData } from '../generated/ResleevingConsole';

export type Data = ResleevingConsoleData;

export type ActiveBodyRecordData = NonNullable<Data['active_b_rec']>;

export type modalMindData = NonNullable<Data['active_m_rec']>;

export type record = Data['bodyrecords'][number];
