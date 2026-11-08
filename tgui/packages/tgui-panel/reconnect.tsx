import { atom, useAtomValue } from 'jotai';
import { useEffect, useState } from 'react';
import { createLogger } from 'tgui/logging';
import { Button } from 'tgui-core/components';
import { store } from './events/store';
import { Reconnector, type ReconnectState } from './reconnect-model';

let url: string | null = null;

setInterval(() => {
  Byond.winget('', 'url').then((currentUrl) => {
    // Sometimes, for whatever reason, BYOND will give an IP with a :0 port.
    if (currentUrl && !currentUrl.match(/:0$/)) {
      url = currentUrl;
    }
  });
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
