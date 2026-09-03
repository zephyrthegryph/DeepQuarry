import { sendByondMessage } from '../events/sendMessage';
import { configAtom, store } from '../events/store';

let sequence = 0;
let flushTimer: number | undefined;
const pendingTransitions: Record<string, unknown>[] = [];

function flushTransitions(): void {
  flushTimer = undefined;
  if (!pendingTransitions.length) return;
  sendByondMessage('perf/transition', {
    kind: 'window-transition-batch',
    events: pendingTransitions.splice(0, pendingTransitions.length),
  });
}

/** Emit one flat, server-persisted event in the native-window transition timeline. */
export function profileTransition(
  stage: string,
  detail: Record<string, unknown> = {},
  force = false,
): void {
  const config = store.get(configAtom);
  if (!force && !config?.client?.profiling) return;
  const flatDetail = Object.fromEntries(
    Object.entries(detail).map(([key, value]) => [
      key,
      value !== null && typeof value === 'object'
        ? JSON.stringify(value)
        : value,
    ]),
  );
  pendingTransitions.push({
    kind: 'window-transition',
    seq: ++sequence,
    at: performance.now?.() ?? Date.now(),
    stage,
    interface: config?.interface?.name,
    generation: config?.window?.generation,
    viewport: `${window.innerWidth}x${window.innerHeight}`,
    ...flatDetail,
  });
  if (pendingTransitions.length >= 40) {
    flushTransitions();
  } else if (flushTimer === undefined) {
    flushTimer = window.setTimeout(flushTransitions, 150);
  }
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
