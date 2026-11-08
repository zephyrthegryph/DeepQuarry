import { atom, useAtomValue } from 'jotai';
import { useEffect, useState } from 'react';
import { createLogger } from 'tgui/logging';
import { Button } from 'tgui-core/components';
import { store } from './events/store';
import { Reconnector, type ReconnectState } from './reconnect-model';

let url: string | null = null;

/** Keeps the server address for a reconnect: only a real address (BYOND sometimes reports a :0 port, or nothing a string). */
export function noteServerUrl(currentUrl: unknown): void {
  if (typeof currentUrl === 'string' && currentUrl && !/:0$/.test(currentUrl)) {
    url = currentUrl;
  }
}

/** The address a reconnect would use (tests). */
export function serverUrl(): string | null {
  return url;
}

// A poll whose answer is not a string, or that fails, keeps the last address: it never throws out of the timer, where it surfaced
// as an error of whatever ran at that moment (the PDA test's 1-in-5 failure).
setInterval(() => {
  Byond.winget('', 'url')
    .then(noteServerUrl)
    .catch(() => undefined);
}, 5000);

const logger = createLogger('Reconnect');

const reconnector = new Reconnector({
  now: () => Date.now(),
  setTimer: (fn, ms) => setTimeout(fn, ms),
  clearTimer: (id) => clearTimeout(id as ReturnType<typeof setTimeout>),
  reconnect: () => Byond.command('.reconnect'),
  log: (message) => logger.log(message),
  onChange: (state) => store.set(reconnectStateAtom, state),
});

export const reconnectStateAtom = atom<ReconnectState>(reconnector.getState());

/** Reconnects by itself while the connection is lost or the round restarts. */
export function useAutoReconnect(down: boolean) {
  useEffect(() => {
    reconnector.setDown(down);
  }, [down]);
}

/** Reconnect state shown inline in the ping indicator: attempt, countdown, buttons. */
export function ReconnectStatus(props: { restarting: boolean }) {
  const state = useAtomValue(reconnectStateAtom);
  const [, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(id);
  }, []);
  let text: string;
  if (state.active) {
    const secs =
      state.nextAt === null
        ? 0
        : Math.max(0, Math.ceil((state.nextAt - Date.now()) / 1000));
    text = `Reconnecting (attempt ${state.attempt + 1}${
      state.nextAt !== null ? `, ${secs}s` : ''
    })`;
  } else if (state.cancelled) {
    text = 'Disconnected';
  } else {
    text = props.restarting ? 'Server restarting' : 'Disconnected';
  }
  return (
    <>
      <span className="Ping__status">{text}</span>
      {state.active ? (
        <Button
          compact
          tooltip="Stop reconnecting automatically"
          tooltipPosition="bottom"
          onClick={() => reconnector.cancel()}
        >
          Cancel
        </Button>
      ) : null}
      <Button
        compact
        tooltip="Reconnect now"
        tooltipPosition="bottom"
        onClick={() => {
          Byond.command('.reconnect');
        }}
      >
        Reconnect
      </Button>
      {url ? (
        <Button
          compact
          icon="power-off"
          tooltip="Relaunch game"
          tooltipPosition="bottom-end"
          onClick={() => {
            location.href = `byond://${url}`;
            Byond.command('.quit');
          }}
        />
      ) : null}
    </>
  );
}
