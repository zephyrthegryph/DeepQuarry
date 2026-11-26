declare let __webpack_public_path__: string;

let installedBaseUrl = '';
const warmedUrls = new Set<string>();
/** The most opened interfaces' chunks: fetched first, WARMUP_CONCURRENCY at a time. */
const pendingUrls: string[] = [];
/** Every other chunk: fetched once the first queue is empty, LOW_CONCURRENCY at a time and at low network priority. */
const lowUrls: string[] = [];
let activeRequests = 0;
let warmupScheduled = false;

const WARMUP_DELAY_MS = 750;
const WARMUP_CONCURRENCY = 6;
const LOW_CONCURRENCY = 2;

/** Point lazy interface imports at the server's content-addressed webroot. */
export function installChunkPublicPath(baseUrl?: string): void {
  const normalized = baseUrl?.trim();
  if (!normalized || normalized === installedBaseUrl) return;
  installedBaseUrl = normalized.endsWith('/') ? normalized : `${normalized}/`;
  __webpack_public_path__ = installedBaseUrl;
}

type ChunkWarmPayload = {
  url?: string;
  files?: string[];
  /** The first this many files belong to the most opened interfaces (server ranking). Absent: all are first. */
  priority?: number;
};

/** Configure a shell and fetch chunks into cache without evaluating modules. */
export function warmChunkPublicPath(payload?: ChunkWarmPayload): void {
  installChunkPublicPath(payload?.url);
  if (!installedBaseUrl || !Array.isArray(payload?.files)) return;
  const priority =
    typeof payload.priority === 'number' ? payload.priority : Infinity;
  payload.files.forEach((file, index) => {
    if (!isSafeChunkFilename(file)) return;
    const url = `${installedBaseUrl}${encodeURIComponent(file)}`;
    if (!warmedUrls.has(url)) {
      warmedUrls.add(url);
      (index < priority ? pendingUrls : lowUrls).push(url);
    }
  });
  scheduleWarmup();
}

function isSafeChunkFilename(file: unknown): file is string {
  return (
    typeof file === 'string' &&
    !file.includes('/') &&
    !file.includes('\\') &&
    (file.endsWith('.chunk.js') || file.endsWith('.chunk.css'))
  );
}

function scheduleWarmup(): void {
  if (warmupScheduled || (!pendingUrls.length && !lowUrls.length)) return;
  warmupScheduled = true;
  window.setTimeout(() => scheduleIdle(pumpWarmup), WARMUP_DELAY_MS);
}

function scheduleIdle(callback: () => void): void {
  const requestIdle = (
    window as typeof window & {
      requestIdleCallback?: (
        callback: () => void,
        options?: { timeout: number },
      ) => number;
    }
  ).requestIdleCallback;
  if (requestIdle) {
    requestIdle(callback, { timeout: 1000 });
  } else {
    window.setTimeout(callback, 16);
  }
}

function pumpWarmup(): void {
  warmupScheduled = false;
  while (pendingUrls.length && activeRequests < WARMUP_CONCURRENCY) {
    fetchChunk(pendingUrls.shift() as string, false);
  }
  // The rest only once the ranked chunks are all requested, a couple at a time.
  while (
    !pendingUrls.length &&
    lowUrls.length &&
    activeRequests < LOW_CONCURRENCY
  ) {
    fetchChunk(lowUrls.shift() as string, true);
  }
}

function fetchChunk(url: string, low: boolean): void {
  activeRequests++;
  fetch(url, {
    cache: 'force-cache',
    mode: 'cors',
    ...(low ? { priority: 'low' } : {}),
  } as RequestInit)
    .then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.arrayBuffer();
    })
    .catch(() => {
      // Normal dynamic import remains the reliable fallback on failed prefetch.
      warmedUrls.delete(url);
    })
    .finally(() => {
      activeRequests--;
      // Keep the bounded queue full. Hidden CEF windows can throttle
      // requestIdleCallback to roughly one callback per second; using it for
      // every refill made a 415-file warmup take several minutes. The initial
      // delay remains idle-gated, while subsequent work is network I/O only.
      if (pendingUrls.length || lowUrls.length) pumpWarmup();
    });
}
