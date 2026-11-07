import { describe, expect, it } from 'bun:test';
import { Reconnector, reconnectDelay } from './reconnect-model';

function setup() {
  let clock = 0;
  const timers: { at: number; fn: () => void; id: number }[] = [];
  let nextId = 1;
  const calls: string[] = [];
  const logs: string[] = [];
  const r = new Reconnector({
    now: () => clock,
    setTimer: (fn, ms) => {
      const id = nextId++;
      timers.push({ at: clock + ms, fn, id });
      return id;
    },
    clearTimer: (id) => {
      const i = timers.findIndex((t) => t.id === id);
      if (i >= 0) timers.splice(i, 1);
    },
    reconnect: () => calls.push('reconnect'),
    log: (m) => logs.push(m),
    onChange: () => {},
  });
  function advance(ms: number) {
    const end = clock + ms;
    for (;;) {
      timers.sort((a, b) => a.at - b.at);
      const t = timers[0];
      if (!t || t.at > end) break;
      timers.shift();
      clock = t.at;
      t.fn();
    }
    clock = end;
  }
  return { r, calls, logs, advance, timers };
}

describe('reconnectDelay', () => {
  it('backs off 2s, 5s, 10s then 15s', () => {
    expect([1, 2, 3, 4, 5, 9].map(reconnectDelay)).toEqual([
      2000, 5000, 10000, 15000, 15000, 15000,
    ]);
  });
});

describe('Reconnector', () => {
  it('reconnects on the backoff schedule while down', () => {
    const { r, calls, advance } = setup();
    r.setDown(true);
    advance(1999);
    expect(calls.length).toBe(0);
    advance(1);
    expect(calls.length).toBe(1);
    advance(5000);
    expect(calls.length).toBe(2);
    advance(10000);
    advance(15000);
    advance(15000);
    expect(calls.length).toBe(5);
    expect(r.getState().attempt).toBe(5);
  });

  it('stops and resets once the connection is back', () => {
    const { r, calls, advance, timers } = setup();
    r.setDown(true);
    advance(2000);
    r.setDown(false);
    expect(timers.length).toBe(0);
    advance(60000);
    expect(calls.length).toBe(1);
    expect(r.getState().active).toBe(false);
    expect(r.getState().attempt).toBe(0);
  });

  it('cancel stops until the connection has come back', () => {
    const { r, calls, advance } = setup();
    r.setDown(true);
    advance(2000);
    r.cancel();
    r.setDown(true);
    advance(60000);
    expect(calls.length).toBe(1);
    r.setDown(false);
    r.setDown(true);
    advance(2000);
    expect(calls.length).toBe(2);
  });

  it('logs every attempt', () => {
    const { r, logs, advance } = setup();
    r.setDown(true);
    advance(7000);
    expect(logs.filter((l) => l.startsWith('reconnect attempt')).length).toBe(
      2,
    );
  });
});
