import { afterEach, beforeEach, describe, expect, it } from 'bun:test';
import { cleanup, render, waitFor } from '@testing-library/react';
import { act } from 'react';
import { EmbeddedContext } from './embedded';
import { guardedDispatch, reportUiError, resetErrorReports } from './errors';
import { RELOAD_FAILS_WITHIN_MS, ReloadBoundary } from './ReloadBoundary';

const byond = (globalThis as any).Byond;
const realSend = byond.sendMessage;
const realNow = Date.now;
const realError = console.error;
let now = 1000000;
let sent: { type: string; payload: any }[] = [];

beforeEach(() => {
  now = 1000000;
  sent = [];
  Date.now = () => now;
  console.error = () => {};
  byond.sendMessage = (type: string, payload: unknown) =>
    sent.push({ type, payload });
  resetErrorReports();
});

afterEach(() => {
  cleanup();
  Date.now = realNow;
  console.error = realError;
  byond.sendMessage = realSend;
});

/** Throws while broken. React itself re-renders once on a crash, so the state, not a count of renders, decides. */
function flaky() {
  const state = { broken: true, message: 'broke' };
  function Content() {
    if (state.broken) throw new Error(state.message);
    return <div>content</div>;
  }
  return { state, Content, fix: () => (state.broken = false) };
}

const outcomes = () => sent.map((message) => message.payload.outcome);

describe('every window reloads once', () => {
  for (const [where, backend] of [
    ['floating', null],
    ['docked', { id: 'col-1' }],
  ] as const) {
    it(`a ${where} window recovers from one crash`, () => {
      const { Content, fix } = flaky();
      const view = render(
        <EmbeddedContext.Provider value={backend as any}>
          <ReloadBoundary name="Thing" onReload={fix}>
            <Content />
          </ReloadBoundary>
        </EmbeddedContext.Provider>,
      );
      expect(view.getByText('content')).toBeTruthy();
      expect(outcomes()).toEqual(['retried']);
      expect(sent[0].type).toBe('wm/error');
    });

    it(`a ${where} window failing again within a second shows the error`, () => {
      const { Content } = flaky();
      const view = render(
        <EmbeddedContext.Provider value={backend as any}>
          <ReloadBoundary name="Thing">
            <Content />
          </ReloadBoundary>
        </EmbeddedContext.Provider>,
      );
      expect(view.getByText('Thing failed: broke')).toBeTruthy();
      expect(view.getByText('Reload')).toBeTruthy();
      expect(outcomes()).toEqual(['retried', 'error-screen']);
    });
  }

  it('a failure over a second after the reload retries again', () => {
    const { state, Content, fix } = flaky();
    const tree = () => (
      <ReloadBoundary name="Thing" onReload={fix}>
        <Content />
      </ReloadBoundary>
    );
    const view = render(tree());
    now += RELOAD_FAILS_WITHIN_MS + 1;
    state.broken = true;
    state.message = 'later';
    view.rerender(tree());
    expect(view.getByText('content')).toBeTruthy();
    expect(outcomes()).toEqual(['retried', 'retried']);
  });

  it('the Reload button tries again', async () => {
    const { Content, fix } = flaky();
    const view = render(
      <ReloadBoundary name="Thing">
        <Content />
      </ReloadBoundary>,
    );
    fix();
    act(() => view.getByText('Reload').click());
    await waitFor(() => expect(view.getByText('content')).toBeTruthy());
  });

  it('keeps what the content attached to a node held outside React', () => {
    // How the chat keeps its history: chatRenderer owns one root node and re-attaches it on mount.
    const history = document.createElement('div');
    history.textContent = 'old line';
    let crash = true;
    function Chat() {
      if (crash) throw new Error('broke');
      return (
        <div
          ref={(node) => {
            node?.appendChild(history);
          }}
        />
      );
    }
    const view = render(
      <ReloadBoundary name="Chat" onReload={() => (crash = false)}>
        <Chat />
      </ReloadBoundary>,
    );
    expect(view.getByText('old line')).toBeTruthy();
  });
});

describe('the reporter', () => {
  const failure = {
    kind: 'render',
    name: 'X',
    error: new Error('same'),
    outcome: 'retried',
  } as const;

  it('sends a repeated failure once, then counts it', () => {
    reportUiError(failure);
    reportUiError(failure);
    reportUiError(failure);
    expect(sent.length).toBe(1);
    now += 10001;
    reportUiError(failure);
    expect(sent.length).toBe(2);
    expect(sent[1].payload.repeats).toBe(2);
  });

  it('stops at the rate limit and says how many it dropped', () => {
    for (let i = 0; i < 35; i++) {
      reportUiError({ ...failure, error: new Error(`e${i}`) });
    }
    expect(sent.length).toBe(30);
    now += 60001;
    reportUiError({ ...failure, error: new Error('next') });
    expect(sent[30].payload.dropped).toBe(5);
  });

  it('a throwing handler is reported and the page carries on', () => {
    guardedDispatch('update', () => {
      throw new Error('bad handler');
    });
    expect(sent[0].payload).toMatchObject({
      kind: 'handler',
      name: 'update',
      outcome: 'continued',
    });
  });
});
