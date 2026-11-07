import { atom, useAtomValue } from 'jotai';
import { useEffect, useState } from 'react';
import { createLogger } from 'tgui/logging';
import { Button, Stack } from 'tgui-core/components';
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

export function ReconnectButton(props: {
  onDismissedWarning: React.Dispatch<React.SetStateAction<boolean>>;
}) {
  if (!url) {
    return null;
  }
  const { onDismissedWarning } = props;

  return (
    <Stack>
      <Stack.Item>
        <Button
          color="white"
          onClick={() => {
            Byond.command('.reconnect');
          }}
        >
          Reconnect
        </Button>
      </Stack.Item>
      <Stack.Item>
        <Button
          color="white"
          icon="power-off"
          tooltip="Relaunch game"
          tooltipPosition="bottom-end"
          onClick={() => {
            location.href = `byond://${url}`;
            Byond.command('.quit');
          }}
        />
      </Stack.Item>
      <Stack.Item>
        <Button
          color="white"
          onClick={() => {
            onDismissedWarning(true);
          }}
        >
          Dismiss
        </Button>
      </Stack.Item>
    </Stack>
  );
}

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

/** The "Reconnecting..." line with a cancel button. */
export function AutoReconnectNotice() {
  const state = useAtomValue(reconnectStateAtom);
  const [, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(id);
  }, []);
  if (!state.active) {
    return null;
  }
  const secs =
    state.nextAt === null
      ? 0
      : Math.max(0, Math.ceil((state.nextAt - Date.now()) / 1000));
  return (
    <Stack align="center">
      <Stack.Item>
        Reconnecting... (attempt {state.attempt + 1}
        {state.nextAt !== null && `, in ${secs}s`})
      </Stack.Item>
      <Stack.Item>
        <Button color="white" onClick={() => reconnector.cancel()}>
          Cancel
        </Button>
      </Stack.Item>
    </Stack>
  );
}
