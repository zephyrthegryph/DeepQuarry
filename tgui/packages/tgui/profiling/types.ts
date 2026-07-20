export type CommitSample = {
  interfaceName: string;
  phase: 'mount' | 'update' | 'nested-update';
  actualDuration: number;
  baseDuration: number;
  startTime: number;
  commitTime: number;
  paintDelay?: number;
};

export type UpdateSample = {
  at: number;
  bytes: number;
  applyDuration: number;
  actionLatency?: number;
  fields?: PayloadFieldSample[];
};

export type PayloadFieldSample = {
  path: string;
  bytes: number;
  items?: number;
};

export type StartupStage =
  | 'document_ready'
  | 'initial_render'
  | 'profiler_requested'
  | 'profiler_loaded'
  | 'backend_received'
  | 'backend_applied'
  | 'route_requested'
  | 'chunk_load_started'
  | 'chunk_load_finished'
  | 'content_committed'
  | 'geometry_started'
  | 'geometry_finished'
  | 'window_revealed'
  | 'first_paint';

export type StartupSample = {
  at: number;
  stage: StartupStage;
  interfaceName?: string;
  detail?: Record<string, string | number | boolean | undefined>;
};

export type ActionSample = {
  action: string;
  at: number;
  bytes: number;
};

export type CursorSample = {
  at: number;
  x: number;
  y: number;
  cursor: string;
  target: string;
  stationary: boolean;
};

export type FrameSample = {
  at: number;
  duration: number;
};

export type TguiProfilerBridge = {
  recordAction: (action: string, bytes: number) => void;
  recordUpdate: (
    bytes: number,
    applyDuration: number,
    fields?: PayloadFieldSample[],
  ) => void;
  recordStartup: (sample: StartupSample) => void;
};

declare global {
  interface Window {
    __tguiProfiler?: TguiProfilerBridge;
    __tguiProfilerStartupQueue?: StartupSample[];
  }
}
