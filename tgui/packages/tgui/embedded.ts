/**
 * Embedded interfaces (doc/rewrite/proposals/window_system.md section 12):
 * one page (the right-hand column) hosts several tgui interfaces at once.
 * Each embedded window has its own jotai store and its own way to talk to
 * the server; `useBackend`, `useLocalState`, `useSharedState` and `act` read
 * them from this context, so an interface renders the same embedded as in its
 * own native window, with no change to the interface.
 */
import { createStore } from 'jotai';
import { createContext } from 'react';
import { installChunkPublicPath } from './chunkPublicPath';
import {
  configAtom,
  gameDataAtom,
  gameStaticDataAtom,
  sharedAtom,
  suspendedAtom,
} from './events/store';
import type { Config } from './events/types';

type Store = ReturnType<typeof createStore>;

export type EmbeddedBackend = {
  /** The window id the server knows this interface by. */
  id: string;
  store: Store;
  /** Sends a message for this window (`act/<name>`, `setSharedState`, ...). */
  send: (type: string, payload?: Record<string, unknown>) => void;
  /** Every message the server sends this window, for interfaces with a protocol of their own (useWindowMessages). */
  listeners: Set<(type: string, payload: unknown) => void>;
};

/** Set inside an embedded window; null in a native tgui window. */
export const EmbeddedContext = createContext<EmbeddedBackend | null>(null);

let active: EmbeddedBackend | null = null;

/**
 * The embedded window the player last pressed: what helpers called outside
 * React (event handlers such as ComplexModal's modalOpen) act on. Null in a
 * native window, where the global store and channel are the only ones.
 */
export function activeEmbedded(): EmbeddedBackend | null {
  return active;
}

export function setActiveEmbedded(backend: EmbeddedBackend | null): void {
  active = backend;
}

/** A fresh backend for window `id`: nothing to show until its first update. */
export function createEmbeddedBackend(
  id: string,
  send: EmbeddedBackend['send'],
): EmbeddedBackend {
  const store = createStore();
  store.set(suspendedAtom, false);
  return { id, store, send, listeners: new Set() };
}

type UpdatePayload = {
  config?: Partial<Config>;
  data?: Record<string, unknown>;
  static_data?: Record<string, unknown>;
  shared?: Record<string, string>;
};

/**
 * Applies a server message to an embedded window's store. Only what an
 * interface reads: config, data, static data and shared state (a native
 * window's geometry, reveal and suspend handling has no meaning in a page).
 */
export function applyEmbeddedMessage(
  backend: EmbeddedBackend,
  type: string,
  payload: unknown,
): void {
  for (const listener of backend.listeners) {
    listener(type, payload);
  }
  if (type !== 'update' || !payload || typeof payload !== 'object') {
    return;
  }
  const update = payload as UpdatePayload;
  const { store } = backend;
  // Lazy interface chunks load from the server's chunk host, as in a native window (events/handlers/update.ts).
  installChunkPublicPath(
    (update.config as { chunk_base_url?: string } | undefined)?.chunk_base_url,
  );
  if (update.config) {
    store.set(configAtom, (prev) => ({ ...prev, ...update.config }) as Config);
  }
  if (update.static_data) {
    store.set(gameStaticDataAtom, (prev) => ({
      ...prev,
      ...update.static_data,
    }));
  }
  if (update.data) {
    store.set(gameDataAtom, (prev) => ({ ...prev, ...update.data }));
  }
  if (update.shared) {
    const next: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(update.shared)) {
      next[key] = value === '' ? undefined : JSON.parse(value);
    }
    store.set(sharedAtom, (prev) => ({ ...prev, ...next }));
  }
}
