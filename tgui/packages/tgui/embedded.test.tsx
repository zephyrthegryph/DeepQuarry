import { afterEach, expect, test } from 'bun:test';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { Provider } from 'jotai';
import { useBackend, useLocalState } from './backend';
import {
  activeEmbedded,
  applyEmbeddedMessage,
  createEmbeddedBackend,
  EmbeddedContext,
} from './embedded';
import { gameDataAtom, store } from './events/store';
import { Window } from './layouts';

afterEach(cleanup);

function Probe() {
  const { data, act } = useBackend<{ name: string }>();
  const [count, setCount] = useLocalState('count', 0);
  return (
    <Window title="Probe">
      <Window.Content>
        <button
          type="button"
          onClick={() => {
            act('press', { who: data.name });
            setCount(count + 1);
          }}
        >
          {data.name} {count}
        </button>
      </Window.Content>
    </Window>
  );
}

function host(id: string, sent: unknown[][]) {
  const backend = createEmbeddedBackend(id, (type, payload) =>
    sent.push([id, type, payload]),
  );
  return backend;
}

test('two embedded windows in one page each read their own data and act on their own channel', () => {
  store.set(gameDataAtom, { name: 'global' });
  const sent: unknown[][] = [];
  const pda = host('w-pda', sent);
  const apc = host('w-apc', sent);
  applyEmbeddedMessage(pda, 'update', {
    config: { interface: { name: 'Probe' } },
    data: { name: 'PDA' },
  });
  applyEmbeddedMessage(apc, 'update', { data: { name: 'APC' } });
  render(
    <>
      {[pda, apc].map((backend) => (
        <Provider key={backend.id} store={backend.store}>
          <EmbeddedContext.Provider value={backend}>
            <div onPointerDownCapture={() => {}}>
              <Probe />
            </div>
          </EmbeddedContext.Provider>
        </Provider>
      ))}
    </>,
  );
  fireEvent.click(screen.getByText('APC 0'));
  expect(sent).toEqual([['w-apc', 'act/press', { who: 'APC' }]]);
  expect(screen.getByText('PDA 0')).toBeTruthy();
  // The page's own (global) store is untouched by either window.
  expect(store.get(gameDataAtom)).toEqual({ name: 'global' });
});

test('a data update merges into the window it is for', () => {
  const backend = host('w1', []);
  applyEmbeddedMessage(backend, 'update', { data: { a: 1, b: 1 } });
  applyEmbeddedMessage(backend, 'update', { data: { b: 2 } });
  applyEmbeddedMessage(backend, 'ping', { data: { a: 9 } });
  expect(backend.store.get(gameDataAtom)).toEqual({ a: 1, b: 2 });
  expect(activeEmbedded()).toBeNull();
});
