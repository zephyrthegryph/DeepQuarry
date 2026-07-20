import { useAtomValue } from 'jotai';
import { useEffect, useState } from 'react';
import {
  Box,
  Button,
  Icon,
  LabeledList,
  ProgressBar,
  Section,
  Stack,
} from 'tgui-core/components';

import { suspendedAtom } from './events/store';
import { profileStartup } from './profiling/hooks';

/**
 * Primes the browser's shared React, style, icon, and layout paths while an idle
 * pooled shell is still hidden. This deliberately imports no interface module:
 * named UI chunks remain demand-loaded on their first real open.
 */
export function GenericWarmup() {
  const suspended = useAtomValue(suspendedAtom);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!suspended || ready) return;
    const warm = () => {
      setReady(true);
      document.fonts?.load('12px "Font Awesome 5 Free"');
      document.fonts?.load('12px tgfont');
      profileStartup('generic_warmup_started');
    };
    const idle = window.requestIdleCallback?.(warm, { timeout: 1000 });
    const fallback =
      idle === undefined ? window.setTimeout(warm, 100) : undefined;
    return () => {
      if (idle !== undefined) window.cancelIdleCallback?.(idle);
      if (fallback !== undefined) window.clearTimeout(fallback);
    };
  }, [ready, suspended]);

  useEffect(() => {
    if (ready) profileStartup('generic_warmup_finished');
  }, [ready]);

  if (!ready) return null;
  return (
    <div
      aria-hidden="true"
      style={{
        contain: 'strict',
        height: 475,
        left: -10000,
        pointerEvents: 'none',
        position: 'fixed',
        top: -10000,
        width: 450,
      }}
    >
      <Section title="Warmup">
        <LabeledList>
          <LabeledList.Item
            label="Controls"
            buttons={<Button icon="power-off">Ready</Button>}
          >
            <ProgressBar value={0.5} />
          </LabeledList.Item>
        </LabeledList>
        <Stack>
          <Stack.Item>
            <Icon name="sync" />
          </Stack.Item>
          <Stack.Item grow>
            <Box>Shared TGUI shell</Box>
          </Stack.Item>
        </Stack>
      </Section>
    </div>
  );
}
