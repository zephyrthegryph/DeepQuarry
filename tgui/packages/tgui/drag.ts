/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { storage } from 'common/storage';
import type { BooleanLike } from 'tgui-core/react';
import { vecAdd, vecMultiply, vecScale, vecSubtract } from 'tgui-core/vector';
import { createLogger } from './logging';

export type Point = [number, number];
type GeometryPayload = Partial<{
  pos: string;
  size: string;
}>;

const logger = createLogger('drag');
const pixelRatio = window.devicePixelRatio ?? 1;
let windowKey = Byond.windowId;
let dragging = false;
let resizing = false;
let screenOffset: Point = [0, 0];
let screenOffsetPromise: Promise<Point> | undefined;
let dragPointOffset: Point;
let resizeMatrix: Point;
let initialSize: Point;
let size: Point;

export type ResolvedWindowGeometry = Partial<{
  pos: Point;
  size: Point;
}>;

type StoredWindowGeometry = {
  pos: Point;
  size: Point;
};

const geometryCache = new Map<string, StoredWindowGeometry | null>();
const geometryRequestCache = new Map<
  string,
  Promise<StoredWindowGeometry | null>
>();

async function readStoredGeometry(
  key: string,
): Promise<StoredWindowGeometry | null> {
  const query = storage.get(key).then((value) => {
    const geometry = (value as StoredWindowGeometry | undefined) || null;
    geometryCache.set(key, geometry);
    return geometry;
  });
  const timeout = new Promise<null>((resolve) => {
    setTimeout(() => resolve(null), 500);
  });
  return Promise.race([query, timeout]);
}

/** Begin the asynchronous storage lookup before the interface route mounts. */
export function prepareWindowGeometry(
  key: string | undefined,
): Promise<StoredWindowGeometry | null> | undefined {
  if (!key || geometryCache.has(key)) {
    return undefined;
  }
  let request = geometryRequestCache.get(key);
  if (!request) {
    request = readStoredGeometry(key).finally(() => {
      geometryRequestCache.delete(key);
    });
    geometryRequestCache.set(key, request);
  }
  return request;
}

let winsetRaf: number | undefined;
let pendingWinset: GeometryPayload = {};
let lastSentWinset: GeometryPayload = {};

/** Expends all stored winset calls in a single call. */
function flushWinset(): void {
  winsetRaf = undefined;

  const payload: GeometryPayload = {};
  if (pendingWinset.pos && pendingWinset.pos !== lastSentWinset.pos) {
    payload.pos = pendingWinset.pos;
  }
  if (pendingWinset.size && pendingWinset.size !== lastSentWinset.size) {
    payload.size = pendingWinset.size;
  }

  pendingWinset = {};

  if (payload.pos || payload.size) {
    Byond.winset(Byond.windowId, payload);
    lastSentWinset = { ...lastSentWinset, ...payload };
  }
}

function scheduleWinset(): void {
  if (winsetRaf !== undefined) {
    return;
  }
  winsetRaf = requestAnimationFrame(flushWinset);
}

function flushWinsetNow(): void {
  if (winsetRaf !== undefined) {
    cancelAnimationFrame(winsetRaf);
    winsetRaf = undefined;
  }
  flushWinset();
}

// Set the window key
export function setWindowKey(key: string): void {
  windowKey = key;
}

// Get window position
export function getWindowPosition(): Point {
  return [window.screenLeft * pixelRatio, window.screenTop * pixelRatio];
}

/** Native-coordinate position observable without a BYOND winget round trip. */
export function getNativeWindowPosition(): Point {
  return vecAdd(getWindowPosition(), screenOffset) as Point;
}

// Get window size
export function getWindowSize(): Point {
  return [window.innerWidth * pixelRatio, window.innerHeight * pixelRatio];
}

// Set window position
export function setWindowPosition(vec: Point): void {
  const byondPos = vecAdd(vec, screenOffset);
  Byond.winset(Byond.windowId, {
    pos: `${byondPos[0]},${byondPos[1]}`,
  });
}

function setWindowPositionBatched(vec: Point): void {
  const byondPos = vecAdd(vec, screenOffset);
  pendingWinset.pos = `${byondPos[0]},${byondPos[1]}`;
  scheduleWinset();
}

function setWindowSizeBatched(vec: Point): void {
  pendingWinset.size = `${vec[0]}x${vec[1]}`;
  scheduleWinset();
}

// Get screen position
function getScreenPosition(): Point {
  return [0 - screenOffset[0], 0 - screenOffset[1]];
}

// Get screen size
function getScreenSize(): Point {
  return [
    window.screen.availWidth * pixelRatio,
    window.screen.availHeight * pixelRatio,
  ];
}

/**
 * Moves an item to the top of the recents array, and keeps its length
 * limited to the number in `limit` argument.
 *
 * Uses a strict equality check for comparisons.
 *
 * Returns new recents and an item which was trimmed.
 */
export function touchRecents(
  recents: string[],
  touchedItem: string,
  limit = 50,
): [string[], string | undefined] {
  const nextRecents: string[] = [touchedItem];
  let trimmedItem: string | undefined;
  for (let i = 0; i < recents.length; i++) {
    const item = recents[i];
    if (item === touchedItem) {
      continue;
    }
    if (nextRecents.length < limit) {
      nextRecents.push(item);
    } else {
      trimmedItem = item;
    }
  }
  return [nextRecents, trimmedItem];
}

// Store window geometry in local storage
export async function storeWindowGeometry(): Promise<void> {
  logger.log('storing geometry');
  const geometry = {
    pos: getWindowPosition(),
    size: getWindowSize(),
  };
  geometryCache.set(windowKey, geometry);
  storage.set(windowKey, geometry);
  // Update the list of stored geometries
  const [geometries, trimmedKey] = touchRecents(
    (await storage.get('geometries')) || [],
    windowKey,
  );
  if (trimmedKey) {
    storage.remove(trimmedKey);
  }
  storage.set('geometries', geometries);
}

type RecallOptions = Partial<{
  pos: Point;
  size: Point;
  locked: BooleanLike;
  scale: BooleanLike;
}>;

// Recall window geometry from local storage and apply it
export async function recallWindowGeometry(
  options: RecallOptions = {},
  preapplied?: ResolvedWindowGeometry,
): Promise<ResolvedWindowGeometry> {
  if (preapplied) {
    // The server has already applied this exact native geometry while the
    // pooled shell was hidden. Preserve the normal scale/drag initialization,
    // but skip persistent storage and coordinate recomputation.
    if (!options.scale) {
      document.body.style.zoom = `${100 / window.devicePixelRatio}%`;
      document.documentElement.style.setProperty(
        '--scaling-amount',
        window.devicePixelRatio.toString(),
      );
    } else {
      document.body.style.zoom = '';
      document.documentElement.style.setProperty('--scaling-amount', null);
    }
    await setupDrag();
    return preapplied;
  }
  let geometry = geometryCache.get(windowKey);
  if (geometry === undefined) {
    geometry =
      (await prepareWindowGeometry(windowKey)) ??
      geometryCache.get(windowKey) ??
      null;
    geometryCache.set(windowKey, geometry);
  }
  if (geometry) {
    logger.log('recalled geometry:', geometry);
  }
  // options.pos is assumed to already be in display-pixels
  let pos = geometry?.pos || options.pos;
  let size = geometry?.size || options.size;
  // Convert size from css-pixels to display-pixels
  if (!geometry?.size && options.scale && size) {
    size = [size[0] * pixelRatio, size[1] * pixelRatio];
  }

  if (!options.scale) {
    document.body.style.zoom = `${100 / window.devicePixelRatio}%`;
    document.documentElement.style.setProperty(
      '--scaling-amount',
      window.devicePixelRatio.toString(),
    );
  } else {
    document.body.style.zoom = '';
    document.documentElement.style.setProperty('--scaling-amount', null);
  }

  // Wait until screen offset gets resolved
  await setupDrag();
  const areaAvailable = getScreenSize();
  const resolved: ResolvedWindowGeometry = {};
  // Resolve window size without mutating the native window yet. Size,
  // position, and visibility are committed together by revealWindow().
  if (size) {
    // Constraint size to not exceed available screen area
    size = [
      Math.min(areaAvailable[0], size[0]),
      Math.min(areaAvailable[1], size[1]),
    ];
    resolved.size = size;
  }
  // Set window position
  if (pos) {
    // Constraint window position if monitor lock was set in preferences.
    if (size && options.locked) {
      pos = constraintPosition(pos, size)[1];
    }
    const nativePos = vecAdd(pos, screenOffset);
    resolved.pos = [nativePos[0], nativePos[1]];
    // Set window position at the center of the screen.
  } else if (size) {
    const centeredPos = vecAdd(
      vecScale(areaAvailable, 0.5),
      vecScale(size, -0.5),
      vecScale(screenOffset, -1.0),
    );
    const nativePos = vecAdd(centeredPos, screenOffset);
    // Native window positions are integral. Sending half-pixels for odd window
    // sizes makes a subsequent winget verification disagree forever after the
    // client rounds them.
    resolved.pos = [Math.round(nativePos[0]), Math.round(nativePos[1])];
  }
  return resolved;
}

// Setup draggable window
export function setupDrag(): Promise<Point> {
  if (screenOffsetPromise) {
    return screenOffsetPromise;
  }
  // Calculate screen offset caused by the windows taskbar
  const windowPosition = getWindowPosition();

  const offsetQuery = Byond.winget(Byond.windowId, 'pos')
    .then(
      (pos): Point => [pos.x - windowPosition[0], pos.y - windowPosition[1]],
    )
    .catch((error): Point => {
      logger.error('failed to query screen offset', error);
      return [0, 0];
    })
    .then((offset) => offset);
  const timeout = new Promise<Point>((resolve) => {
    setTimeout(() => resolve([0, 0]), 500);
  });
  screenOffsetPromise = Promise.race([offsetQuery, timeout]).then((offset) => {
    screenOffset = offset;
    logger.debug('screen offset', screenOffset);
    return offset;
  });
  return screenOffsetPromise;
}

/**
 * Constraints window position to safe screen area, accounting for safe
 * margins which could be a system taskbar.
 */
function constraintPosition(pos: Point, size: Point): [boolean, Point] {
  const screenPos = getScreenPosition();
  const screenSize = getScreenSize();
  const nextPos: Point = [pos[0], pos[1]];
  let relocated = false;

  for (let i = 0; i < 2; i++) {
    const leftBoundary = screenPos[i];
    const rightBoundary = screenPos[i] + screenSize[i];
    if (pos[i] < leftBoundary) {
      nextPos[i] = leftBoundary;
      relocated = true;
    } else if (pos[i] + size[i] > rightBoundary) {
      nextPos[i] = rightBoundary - size[i];
      relocated = true;
    }
  }
  return [relocated, nextPos];
}

// Start dragging the window
export function dragStartHandler(event): void {
  logger.log('drag start');
  dragging = true;
  dragPointOffset = vecSubtract(
    [event.screenX * pixelRatio, event.screenY * pixelRatio],
    getWindowPosition(),
  ) as Point;
  // Focus click target
  (event.target as HTMLElement)?.focus();
  document.addEventListener('mousemove', dragMoveHandler);
  document.addEventListener('mouseup', dragEndHandler);
  dragMoveHandler(event);
}

// End dragging the window
function dragEndHandler(event): void {
  logger.log('drag end');
  dragMoveHandler(event);
  flushWinsetNow();
  document.removeEventListener('mousemove', dragMoveHandler);
  document.removeEventListener('mouseup', dragEndHandler);
  dragging = false;
  storeWindowGeometry();
}

// Move the window while dragging
function dragMoveHandler(event: MouseEvent): void {
  if (!dragging) {
    return;
  }
  event.preventDefault();
  setWindowPositionBatched(
    vecSubtract(
      [event.screenX * pixelRatio, event.screenY * pixelRatio],
      dragPointOffset,
    ) as Point,
  );
}

// Start resizing the window
export const resizeStartHandler =
  (x: number, y: number) =>
  (event: MouseEvent): void => {
    resizeMatrix = [x, y];
    logger.log('resize start', resizeMatrix);
    resizing = true;
    dragPointOffset = vecSubtract(
      [event.screenX * pixelRatio, event.screenY * pixelRatio],
      getWindowPosition(),
    ) as Point;
    initialSize = getWindowSize();
    // Focus click target
    (event.target as HTMLElement)?.focus();
    document.addEventListener('mousemove', resizeMoveHandler);
    document.addEventListener('mouseup', resizeEndHandler);
    resizeMoveHandler(event);
  };

// End resizing the window
function resizeEndHandler(event: MouseEvent): void {
  logger.log('resize end', size);
  resizeMoveHandler(event);
  flushWinsetNow();
  document.removeEventListener('mousemove', resizeMoveHandler);
  document.removeEventListener('mouseup', resizeEndHandler);
  resizing = false;
  storeWindowGeometry();
}

// Move the window while resizing
function resizeMoveHandler(event: MouseEvent): void {
  if (!resizing) {
    return;
  }
  event.preventDefault();
  const currentOffset = vecSubtract(
    [event.screenX * pixelRatio, event.screenY * pixelRatio],
    getWindowPosition(),
  );
  const delta = vecSubtract(currentOffset, dragPointOffset);
  // Extra 1x1 area is added to ensure the browser can see the cursor
  size = vecAdd(initialSize, vecMultiply(resizeMatrix, delta), [1, 1]) as [
    number,
    number,
  ];
  // Sane window size values
  size[0] = Math.max(size[0], 150 * pixelRatio);
  size[1] = Math.max(size[1], 50 * pixelRatio);
  setWindowSizeBatched(size);
}
