import { configAtom, store } from '../events/store';

let sequence = 0;

/** Emit one flat, server-persisted event in the native-window transition timeline. */
export function profileTransition(
  stage: string,
  detail: Record<string, string | number | boolean | undefined> = {},
  force = false,
): void {
  const config = store.get(configAtom);
  if (!force && !config?.client?.profiling) return;
  Byond.sendMessage('perf/transition', {
    kind: 'window-transition',
    seq: ++sequence,
    at: performance.now?.() ?? Date.now(),
    stage,
    interface: config?.interface?.name,
    generation: config?.window?.generation,
    viewport: `${window.innerWidth}x${window.innerHeight}`,
    ...detail,
  });
}

export function observedNativeGeometry(observed: any): Record<string, string> {
  const result: Record<string, string> = {};
  if (observed?.size)
    result.native_size = `${observed.size.x}x${observed.size.y}`;
  if (observed?.pos) result.native_pos = `${observed.pos.x},${observed.pos.y}`;
  if (observed?.alpha !== undefined) result.native_alpha = `${observed.alpha}`;
  if (observed?.['is-visible'] !== undefined) {
    result.native_visible = `${observed['is-visible']}`;
  }
  return result;
}
