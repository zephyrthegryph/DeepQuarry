import { afterEach, describe, expect, test } from 'bun:test';
import { registerInterfacePreparer } from '../../interfacePreparation';
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
  registerInterfacePreparer(undefined);
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

  test('keeps a cold interface suspended until its module is prepared', async () => {
    let finishPreparation: (() => void) | undefined;
    registerInterfacePreparer(
      () =>
        new Promise<void>((resolve) => {
          finishPreparation = resolve;
        }),
    );

    update({
      config: {
        interface: { name: 'ColdInterface' },
        window: { generation: 3, size: [700, 500] },
      } as Config,
      data: { fresh: true },
      static_data: {},
    } as unknown as UpdatePayload);

    expect(Boolean(store.get(suspendedAtom))).toBeTrue();
    finishPreparation?.();
    await Promise.resolve();
    expect(store.get(suspendedAtom)).toBeFalse();
  });

  test('does not resume a superseded cold interface', async () => {
    const resolvers = new Map<string, () => void>();
    registerInterfacePreparer(
      (name) =>
        new Promise<void>((resolve) => {
          resolvers.set(name, resolve);
        }),
    );

    const coldUpdate = (name: string, generation: number) =>
      update({
        config: {
          interface: { name },
          window: { generation, size: [700, 500] },
        } as Config,
        data: { name },
        static_data: {},
      } as unknown as UpdatePayload);

    coldUpdate('FirstInterface', 4);
    coldUpdate('SecondInterface', 5);
    resolvers.get('FirstInterface')?.();
    await Promise.resolve();
    expect(Boolean(store.get(suspendedAtom))).toBeTrue();
    expect(store.get(configAtom).interface?.name).toBe('SecondInterface');

    resolvers.get('SecondInterface')?.();
    await Promise.resolve();
    expect(store.get(suspendedAtom)).toBeFalse();
  });
});
