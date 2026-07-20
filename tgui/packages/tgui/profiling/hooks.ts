import type {
  PayloadFieldSample,
  StartupSample,
  StartupStage,
  TguiProfilerBridge,
} from './types';

function bridge(): TguiProfilerBridge | undefined {
  if (process.env.NODE_ENV !== 'development') return undefined;
  return window.__tguiProfiler;
}

export function profileAction(action: string, bytes: number): void {
  bridge()?.recordAction(action, bytes);
}

export function profileUpdate(
  bytes: number,
  applyDuration: number,
  fields?: PayloadFieldSample[],
): void {
  bridge()?.recordUpdate(bytes, applyDuration, fields);
}

export function profileStartup(
  stage: StartupStage,
  interfaceName?: string,
  detail?: StartupSample['detail'],
): void {
  if (process.env.NODE_ENV !== 'development') return;
  const sample = {
    at: performance.now?.() ?? Date.now(),
    stage,
    interfaceName,
    detail,
  };
  const profiler = bridge();
  if (profiler) {
    profiler.recordStartup(sample);
    return;
  }
  if (!window.__tguiProfilerStartupQueue) {
    window.__tguiProfilerStartupQueue = [];
  }
  window.__tguiProfilerStartupQueue.push(sample);
}
