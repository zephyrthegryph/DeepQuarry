import type { MessageMonitorData } from '../generated/MessageMonitor';

export type Data = MessageMonitorData;

export type LinkedServer = NonNullable<Data['linkedServer']>;
