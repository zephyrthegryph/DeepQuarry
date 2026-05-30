// Electropack tuning panel — TGUI.
//
// Lets a holder adjust the electropack's broadcast frequency and shock
// code, and toggle its power. All three controls flow through tgui_act;
// no embedded byond:// hrefs.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Data = {
  on: BooleanLike;
  frequency: number;
  freq_display: string;
  code: number;
};

export const Electropack = () => {
  const { data, act } = useBackend<Data>();
  const { on, freq_display, code } = data;
  return (
    <Window width={360} height={220}>
      <Window.Content>
        <Section title="Electropack">
          <Box mb={1}>
            <Button icon="power-off" selected={on} onClick={() => act('power')}>
              {on ? 'On' : 'Off'}
            </Button>
          </Box>
          <LabeledList>
            <LabeledList.Item label="Frequency">
              <Button onClick={() => act('freq', { delta: -10 })}>−10</Button>{' '}
              <Button onClick={() => act('freq', { delta: -2 })}>−2</Button>
              <Box inline bold mx={1}>
                {freq_display}
              </Box>
              <Button onClick={() => act('freq', { delta: 2 })}>+2</Button>{' '}
              <Button onClick={() => act('freq', { delta: 10 })}>+10</Button>
            </LabeledList.Item>
            <LabeledList.Item label="Code">
              <Button onClick={() => act('code', { delta: -5 })}>−5</Button>{' '}
              <Button onClick={() => act('code', { delta: -1 })}>−1</Button>
              <Box inline bold mx={1}>
                {code}
              </Box>
              <Button onClick={() => act('code', { delta: 1 })}>+1</Button>{' '}
              <Button onClick={() => act('code', { delta: 5 })}>+5</Button>
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
