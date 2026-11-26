import type { PlayerLogViewerData } from '../generated/PlayerLogViewer';

type LogEntry = PlayerLogViewerData['entries'][string][number];

export type ExtendedLogEntry = { category: string } & Required<LogEntry>;
