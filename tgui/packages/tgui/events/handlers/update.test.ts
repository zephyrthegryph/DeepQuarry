import { afterEach, describe, expect, test } from 'bun:test';
import {
  configAtom,
  gameDataAtom,
  gameStaticDataAtom,
  store,
  suspendedAtom,
} from '../store';
import type { BackendState, Config } from '../types';
import { update } from './update';

type UpdatePayload = Omit<BackendState<Record<string, unknown>>, 'act'> & {
  static_data: Record<string, unknown>;
};

afterEach(() => {
  store.set(configAtom, {} as Config);
  store.set(gameDataAtom, {});
  store.set(gameStaticDataAtom, {});
  store.set(suspendedAtom, Date.now());
});

describe('backend resume ordering', () => {
  test('installs new config and data before the shell becomes renderable', () => {
    store.set(configAtom, {
      interface: { name: 'PreviousInterface' },
      window: { generation: 1, size: [400, 600] },
    } as Config);
    store.set(gameDataAtom, { stale: true });
    store.set(suspendedAtom, Date.now());

    const snapshots: Array<{
      interfaceName?: string;
      generation?: number;
      data: Record<string, unknown>;
    }> = [];
    const unsubscribe = store.sub(suspendedAtom, () => {
      if (!store.get(suspendedAtom)) {
        snapshots.push({
          interfaceName: store.get(configAtom).interface?.name,
          generation: store.get(configAtom).window?.generation,
          data: store.get(gameDataAtom),
        });
      }
    });

    update({
      config: {
        interface: { name: 'ColdInterface' },
        window: { generation: 2, size: [700, 500] },
      } as Config,
      data: { fresh: true },
      static_data: { catalog: 'ready' },
    } as unknown as UpdatePayload);
    unsubscribe();

    expect(snapshots).toEqual([
      {
        interfaceName: 'ColdInterface',
        generation: 2,
        data: { fresh: true },
      },
    ]);
    expect(store.get(gameStaticDataAtom)).toEqual({ catalog: 'ready' });
  });
});
