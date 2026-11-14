/**
 * A window's scroll position outlives the window: reopening an interface
 * (docked or floating, a column part or a native window of its own) puts its
 * content back where it was left. Kept per interface name, in the page's
 * memory (a window that moves between pages of one process) and in the
 * client's storage (a native window is a fresh page every time).
 */
import { type RefObject, useLayoutEffect } from 'react';
import { storage } from 'common/storage';

const KEY_PREFIX = 'scroll-';
const SAVE_DELAY_MS = 500;
/** How long after opening the saved position is still being restored: content that arrives late makes the page tall enough only then. */
export const RESTORE_WINDOW_MS = 2000;
const GRACE_MS = 300;

const memory = new Map<string, number>();

/** The position last remembered for an interface in this page, or undefined. */
export function rememberedScroll(key: string): number | undefined {
  return memory.get(key);
}

export function rememberScroll(key: string, top: number): void {
  memory.set(key, Math.max(0, Math.round(top)));
}

export function useScrollMemory(
  ref: RefObject<HTMLElement | null>,
  key: string | undefined,
  enabled: boolean,
): void {
  useLayoutEffect(() => {
    const node = ref.current;
    if (!node || !key || !enabled) return;
    let target: number | undefined = memory.get(key);
    // Once the player scrolls (or the position is reached) the restore stops.
    let restoring = true;
    let saveTimer: ReturnType<typeof setTimeout> | undefined;
    const startedAt = Date.now();
    const apply = () => {
      if (!restoring || target === undefined) return;
      node.scrollTop = target;
      if (
        Math.abs(node.scrollTop - target) < 1 ||
        Date.now() - startedAt > RESTORE_WINDOW_MS
      ) {
        restoring = false;
      }
    };
    if (target === undefined) {
      Promise.resolve(storage.get(`${KEY_PREFIX}${key}`))
        .then((stored) => {
          if (typeof stored === 'number' && target === undefined) {
            target = stored;
            apply();
          }
        })
        .catch(() => undefined);
    } else {
      apply();
    }
    const onScroll = () => {
      // The scrolls of the restore itself (the page clamps them while content is short) are not the player's: they must not overwrite the
      // remembered position. After a short grace the first scroll is the player's, and the restore stops.
      if (restoring && target !== undefined) {
        if (Math.abs(node.scrollTop - target) < 1) return;
        if (Date.now() - startedAt < GRACE_MS) return;
        restoring = false;
      }
      memory.set(key, Math.round(node.scrollTop));
      clearTimeout(saveTimer);
      saveTimer = setTimeout(() => {
        storage.set(`${KEY_PREFIX}${key}`, memory.get(key));
      }, SAVE_DELAY_MS);
    };
    node.addEventListener('scroll', onScroll, { passive: true });
    const observer = new ResizeObserver(apply);
    for (const child of Array.from(node.children)) observer.observe(child);
    return () => {
      node.removeEventListener('scroll', onScroll);
      observer.disconnect();
      if (saveTimer !== undefined) {
        clearTimeout(saveTimer);
        const top = memory.get(key);
        if (top !== undefined) storage.set(`${KEY_PREFIX}${key}`, top);
      }
    };
  }, [key, enabled]);
}
