import {
  Profiler,
  type ProfilerOnRenderCallback,
  type ReactNode,
  useEffect,
  useState,
  useSyncExternalStore,
} from 'react';
import { configAtom, store } from '../events/store';
import { appendBounded, summarizeProfiler } from './metrics';
import type {
  ActionSample,
  CommitSample,
  CursorSample,
  FrameSample,
  StartupSample,
  UpdateSample,
} from './types';

type ProfileState = {
  actions: ActionSample[];
  commits: CommitSample[];
  cursors: CursorSample[];
  frames: FrameSample[];
  updates: UpdateSample[];
  startup: StartupSample[];
};

const emptyState = (): ProfileState => ({
  actions: [],
  commits: [],
  cursors: [],
  frames: [],
  updates: [],
  startup: [],
});

let state = emptyState();
let pendingAction: ActionSample | undefined;
const listeners = new Set<() => void>();
let lastNotification = 0;
let startupSessionActive = false;
let startupStages = new Set<string>();

function publish(next: ProfileState, immediate = false): void {
  state = next;
  const at = now();
  // Sampling happens every animation frame. Updating the overlay at that rate would
  // itself distort frame timing, so its display refreshes at most four times/second.
  if (!immediate && at - lastNotification < 250) return;
  lastNotification = at;
  for (const listener of listeners) listener();
}

function add<K extends keyof ProfileState>(
  key: K,
  sample: ProfileState[K][number],
) {
  const samples = state[key] as Array<ProfileState[K][number]>;
  publish({ ...state, [key]: appendBounded(samples, sample) } as ProfileState);
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function now(): number {
  return performance.now?.() ?? Date.now();
}

function installBridge(): () => void {
  window.__tguiProfiler = {
    recordAction(action, bytes) {
      const sample = { action, bytes, at: now() };
      pendingAction = sample;
      add('actions', sample);
    },
    recordUpdate(bytes, applyDuration, fields) {
      const at = now();
      const actionLatency = pendingAction ? at - pendingAction.at : undefined;
      add('updates', {
        at,
        bytes,
        applyDuration,
        actionLatency:
          actionLatency !== undefined && actionLatency <= 5000
            ? actionLatency
            : undefined,
        fields,
      });
      pendingAction = undefined;
    },
    recordStartup: recordStartupSample,
  };
  for (const sample of window.__tguiProfilerStartupQueue || []) {
    recordStartupSample(sample);
  }
  delete window.__tguiProfilerStartupQueue;
  return () => {
    delete window.__tguiProfiler;
  };
}

function recordStartupSample(sample: StartupSample): void {
  if (sample.stage === 'backend_received') {
    startupSessionActive = true;
    startupStages = new Set<string>();
  }
  const isDocumentStage =
    sample.stage === 'document_ready' ||
    sample.stage === 'initial_render' ||
    sample.stage === 'profiler_requested' ||
    sample.stage === 'profiler_loaded';
  if (!startupSessionActive && !isDocumentStage) return;
  const key = `${sample.stage}:${sample.interfaceName || ''}`;
  if (startupStages.has(key)) return;
  startupStages.add(key);
  add('startup', sample);
}

function targetName(element: Element | null): string {
  if (!element) return '(none)';
  const id = element.id ? `#${element.id}` : '';
  const classes = [...element.classList].slice(0, 3).join('.');
  return `${element.tagName.toLowerCase()}${id}${classes ? `.${classes}` : ''}`;
}

function installRuntimeObservers(): () => void {
  let lastFrame = now();
  let frameId = 0;
  let x = -1;
  let y = -1;
  let moved = false;
  let lastCursorSignature = '';

  const pointerMove = (event: PointerEvent) => {
    moved = event.clientX !== x || event.clientY !== y;
    x = event.clientX;
    y = event.clientY;
  };
  window.addEventListener('pointermove', pointerMove, { passive: true });

  const frame = (at: number) => {
    try {
      const duration = at - lastFrame;
      lastFrame = at;
      add('frames', { at, duration });
      if (x >= 0 && y >= 0 && document.elementFromPoint) {
        const element = document.elementFromPoint(x, y);
        const cursor = element ? getComputedStyle(element).cursor : '(none)';
        const target = targetName(element);
        const signature = `${cursor}|${target}|${moved}`;
        if (signature !== lastCursorSignature) {
          add('cursors', { at, x, y, cursor, target, stationary: !moved });
          lastCursorSignature = signature;
        }
        moved = false;
      }
    } catch (error) {
      // Profiling is diagnostic and must never interfere with the interface.
      console.error('TGUI profiler frame sampling failed:', error);
    }
    frameId = requestAnimationFrame(frame);
  };
  frameId = requestAnimationFrame(frame);
  return () => {
    cancelAnimationFrame(frameId);
    window.removeEventListener('pointermove', pointerMove);
  };
}

const onRender: ProfilerOnRenderCallback = (
  _id,
  phase,
  actualDuration,
  baseDuration,
  startTime,
  commitTime,
) => {
  const interfaceName = store.get(configAtom)?.interface?.name || '(unknown)';
  const sample: CommitSample = {
    interfaceName,
    phase,
    actualDuration,
    baseDuration,
    startTime,
    commitTime,
  };
  add('commits', sample);
  window.__tguiProfiler?.recordStartup({
    at: commitTime,
    stage: 'content_committed',
    interfaceName,
    detail: { phase, actualDuration },
  });
  requestAnimationFrame(() => {
    requestAnimationFrame((paintedAt) => {
      sample.paintDelay = paintedAt - commitTime;
      window.__tguiProfiler?.recordStartup({
        at: paintedAt,
        stage: 'first_paint',
        interfaceName,
      });
      publish({ ...state, commits: [...state.commits] });
    });
  });
};

function format(value: number): string {
  return `${value.toFixed(value < 10 ? 1 : 0)} ms`;
}

function downloadReport(): void {
  const report = JSON.stringify(
    {
      generatedAt: new Date().toISOString(),
      summary: summarizeProfiler(state),
      samples: state,
    },
    null,
    2,
  );
  Byond.saveBlob(
    new Blob([report], { type: 'application/json' }),
    `tgui-profile-${Date.now()}.json`,
    '.json',
  );
}

function ProfilerOverlay() {
  const snapshot = useSyncExternalStore(subscribe, () => state);
  const [expanded, setExpanded] = useState(false);
  const summary = summarizeProfiler(snapshot);
  const suspiciousCursor =
    summary.stationaryCursorChanges > 0 || summary.stationaryTargetChanges > 0;
  const startup = summary.latestStartup;
  const largestFields = [...(snapshot.updates.at(-1)?.fields || [])]
    .sort((a, b) => b.bytes - a.bytes)
    .slice(0, 3);
  return (
    <aside style={overlayStyle} data-tgui-profiler="true">
      <button
        type="button"
        style={headerStyle}
        onClick={() => setExpanded(!expanded)}
      >
        TGUI PERF {format(summary.commitP95)} p95
      </button>
      {expanded && (
        <div style={{ padding: 8, lineHeight: 1.5 }}>
          <div>
            Commits: {summary.commits} · avg {format(summary.commitAverage)}
          </div>
          <div>Worst commit: {format(summary.commitWorst)}</div>
          <div>
            Updates: {summary.updates} · avg {format(summary.updateAverage)}
          </div>
          <div>Payload: {Math.round(summary.updateBytesAverage)} B avg</div>
          <div
            style={{ color: summary.oversizedUpdates ? '#ffca55' : undefined }}
          >
            Payload worst: {Math.round(summary.updateBytesWorst / 1024)} KB ·
            oversized: {summary.oversizedUpdates}
          </div>
          <div>Action round-trip p95: {format(summary.actionRoundTripP95)}</div>
          <div>
            Frame p95: {format(summary.frameP95)} · stalls: {summary.longFrames}
          </div>
          <div>Commits over one 60Hz frame: {summary.slowCommits}</div>
          {startup && (
            <div
              style={{
                borderTop: '1px solid #315266',
                marginTop: 5,
                paddingTop: 5,
              }}
            >
              <div>
                Startup: {startup.interfaceName || '(unknown)'} Â·{' '}
                {startup.prewarmed ? 'warm shell' : 'cold shell'}
              </div>
              <div>Geometry probe: {format(startup.geometryProbe)}</div>
              {!!startup.serverPreBackend && (
                <div>
                  Server before backend: {format(startup.serverPreBackend)}
                </div>
              )}
              {!!startup.serverCatalogBuild && (
                <div>Catalog build: {format(startup.serverCatalogBuild)}</div>
              )}
              {!!startup.serverPreviewRender && (
                <div>Preview render: {format(startup.serverPreviewRender)}</div>
              )}
              <div>Backend → commit: {format(startup.backendToCommit)}</div>
              <div>Chunk load: {format(startup.chunkLoad)}</div>
              <div>Commit → paint: {format(startup.commitToPaint)}</div>
              <div>Backend → reveal: {format(startup.backendToReveal)}</div>
            </div>
          )}
          {!!largestFields.length && (
            <div style={{ marginTop: 5 }}>
              Largest fields:{' '}
              {largestFields
                .map(
                  (field) =>
                    `${field.path} ${Math.round(field.bytes / 1024)}KB`,
                )
                .join(', ')}
            </div>
          )}
          <div style={{ color: suspiciousCursor ? '#ffca55' : '#86efac' }}>
            Cursor while stationary: {summary.stationaryCursorChanges} cursor /{' '}
            {summary.stationaryTargetChanges} target changes
          </div>
          <div style={{ opacity: 0.7 }}>
            If visual flicker occurs while both stay zero, the embedded-browser
            compositor is implicated.
          </div>
          <div style={{ display: 'flex', gap: 6, marginTop: 6 }}>
            <button type="button" onClick={() => publish(emptyState(), true)}>
              Reset
            </button>
            <button type="button" onClick={downloadReport}>
              Export JSON
            </button>
          </div>
        </div>
      )}
    </aside>
  );
}

const overlayStyle = {
  background: 'rgba(8, 12, 18, 0.94)',
  border: '1px solid #4e9ac7',
  bottom: 6,
  color: '#e8f4ff',
  fontFamily: 'monospace',
  fontSize: 11,
  maxWidth: 340,
  position: 'fixed',
  right: 6,
  zIndex: 2147483647,
} as const;

const headerStyle = {
  background: '#17364a',
  border: 0,
  color: '#e8f4ff',
  cursor: 'pointer',
  fontFamily: 'inherit',
  padding: '5px 8px',
  width: '100%',
} as const;

export function DevelopmentProfiler({ children }: { children: ReactNode }) {
  useEffect(() => {
    const removeBridge = installBridge();
    const removeObservers = installRuntimeObservers();
    return () => {
      removeObservers();
      removeBridge();
    };
  }, []);
  return (
    <>
      <Profiler id="tgui" onRender={onRender}>
        {children}
      </Profiler>
      <ProfilerOverlay />
    </>
  );
}
