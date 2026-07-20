import type {
  ActionSample,
  CommitSample,
  CursorSample,
  FrameSample,
  StartupSample,
  StartupStage,
  UpdateSample,
} from './types';

export const SAMPLE_LIMIT = 500;

export function appendBounded<T>(samples: T[], sample: T): T[] {
  if (samples.length < SAMPLE_LIMIT) return [...samples, sample];
  return [...samples.slice(1), sample];
}

export function percentile(values: number[], amount: number): number {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[
    Math.min(sorted.length - 1, Math.floor(sorted.length * amount))
  ];
}

export type ProfilerSummary = {
  commits: number;
  commitAverage: number;
  commitP95: number;
  commitWorst: number;
  updates: number;
  updateAverage: number;
  updateBytesAverage: number;
  updateBytesWorst: number;
  oversizedUpdates: number;
  actionRoundTrips: number;
  actionRoundTripP95: number;
  frames: number;
  frameP95: number;
  longFrames: number;
  slowCommits: number;
  cursorChanges: number;
  stationaryCursorChanges: number;
  stationaryTargetChanges: number;
  latestStartup?: StartupSummary;
};

export type StartupSummary = {
  interfaceName?: string;
  prewarmed: boolean;
  geometryProbe: number;
  serverPreBackend: number;
  serverCatalogBuild: number;
  serverPreviewRender: number;
  backendToChunk: number;
  chunkLoad: number;
  backendToCommit: number;
  commitToPaint: number;
  backendToReveal: number;
  documentToReveal: number;
};

export function summarizeProfiler(samples: {
  actions: ActionSample[];
  commits: CommitSample[];
  cursors: CursorSample[];
  frames: FrameSample[];
  updates: UpdateSample[];
  startup?: StartupSample[];
}): ProfilerSummary {
  const commitTimes = samples.commits.map((sample) => sample.actualDuration);
  const updateTimes = samples.updates.map((sample) => sample.applyDuration);
  const roundTrips = samples.updates
    .map((sample) => sample.actionLatency)
    .filter((value): value is number => value !== undefined);
  const frameTimes = samples.frames.map((sample) => sample.duration);
  let cursorChanges = 0;
  let stationaryCursorChanges = 0;
  let stationaryTargetChanges = 0;
  for (let i = 1; i < samples.cursors.length; i++) {
    const previous = samples.cursors[i - 1];
    const current = samples.cursors[i];
    const samePoint = previous.x === current.x && previous.y === current.y;
    if (samePoint && previous.cursor !== current.cursor) {
      cursorChanges++;
      if (current.stationary) stationaryCursorChanges++;
    }
    if (samePoint && current.stationary && previous.target !== current.target) {
      stationaryTargetChanges++;
    }
  }
  return {
    commits: commitTimes.length,
    commitAverage: average(commitTimes),
    commitP95: percentile(commitTimes, 0.95),
    commitWorst: Math.max(0, ...commitTimes),
    updates: updateTimes.length,
    updateAverage: average(updateTimes),
    updateBytesAverage: average(samples.updates.map((sample) => sample.bytes)),
    updateBytesWorst: Math.max(
      0,
      ...samples.updates.map((sample) => sample.bytes),
    ),
    oversizedUpdates: samples.updates.filter((sample) => sample.bytes > 100_000)
      .length,
    actionRoundTrips: roundTrips.length,
    actionRoundTripP95: percentile(roundTrips, 0.95),
    frames: frameTimes.length,
    frameP95: percentile(frameTimes, 0.95),
    longFrames: frameTimes.filter((duration) => duration > 50).length,
    slowCommits: commitTimes.filter((duration) => duration > 16.7).length,
    cursorChanges,
    stationaryCursorChanges,
    stationaryTargetChanges,
    latestStartup: summarizeLatestStartup(samples.startup || []),
  };
}

export function summarizeLatestStartup(
  samples: StartupSample[],
): StartupSummary | undefined {
  const backendIndex = samples.findLastIndex(
    (sample) => sample.stage === 'backend_received',
  );
  if (backendIndex < 0) return undefined;
  const session = samples.slice(backendIndex);
  const backend = session[0];
  const time = (stage: StartupStage) =>
    session.find((sample) => sample.stage === stage)?.at;
  const difference = (from: number | undefined, to: number | undefined) =>
    from === undefined || to === undefined ? 0 : Math.max(0, to - from);
  const documentReady = samples.find(
    (sample) => sample.stage === 'document_ready',
  )?.at;
  const geometryProbeStarted = samples.find(
    (sample) => sample.stage === 'geometry_probe_started',
  )?.at;
  const geometryProbeFinished = samples.find(
    (sample) => sample.stage === 'geometry_probe_finished',
  )?.at;
  const serverProfile = session.find(
    (sample) => sample.stage === 'server_profile',
  )?.detail;
  const chunkStart = time('chunk_load_started');
  return {
    interfaceName: backend.interfaceName,
    prewarmed: Boolean(backend.detail?.prewarmed),
    geometryProbe: difference(geometryProbeStarted, geometryProbeFinished),
    serverPreBackend: Number(serverProfile?.pre_backend_ms || 0),
    serverCatalogBuild: Number(serverProfile?.catalog_build_ms || 0),
    serverPreviewRender: Number(serverProfile?.preview_render_ms || 0),
    backendToChunk: difference(backend.at, chunkStart),
    chunkLoad: difference(chunkStart, time('chunk_load_finished')),
    backendToCommit: difference(backend.at, time('content_committed')),
    commitToPaint: difference(time('content_committed'), time('first_paint')),
    backendToReveal: difference(backend.at, time('window_revealed')),
    documentToReveal: difference(documentReady, time('window_revealed')),
  };
}

function average(values: number[]): number {
  return values.length
    ? values.reduce((total, value) => total + value, 0) / values.length
    : 0;
}
