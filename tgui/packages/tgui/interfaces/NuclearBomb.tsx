// Nuclear fission explosive — TGUI.
//
// Two views in one window:
//   - main (attack_hand with extended=TRUE): auth + keypad + timer/safety/anchor.
//   - wires (wirecutter/multitool on opened panel): cut/mend each wire,
//     pulse with a multitool, plus the audible/visual tells (whirring,
//     shaking, light state).
// The DM side toggles `wire_view` to switch which view is shown.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type WireEntry = {
  name: string;
  cut: BooleanLike;
};

type Data = {
  wire_view: BooleanLike;
  // main view
  auth: BooleanLike;
  yes_code: BooleanLike;
  timing: BooleanLike;
  timeleft: number;
  safety: BooleanLike;
  anchored: BooleanLike;
  code_display: string;
  status_label: string;
  // wire view
  wires: WireEntry[];
  lighthack: BooleanLike;
};

const KEYPAD: Array<string[]> = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['R', '0', 'E'],
];

export const NuclearBomb = () => {
  const { data } = useBackend<Data>();
  return (
    <Window width={400} height={540}>
      <Window.Content>
        {data.wire_view ? <WireView /> : <MainView />}
      </Window.Content>
    </Window>
  );
};

const MainView = () => {
  const { data, act } = useBackend<Data>();
  const {
    auth,
    yes_code,
    timing,
    timeleft,
    safety,
    anchored,
    code_display,
    status_label,
  } = data;

  const canControl = !!auth && !!yes_code;

  return (
    <>
      <Section title="Nuclear Fission Explosive">
        <LabeledList>
          <LabeledList.Item label="Auth Disk">
            <Button color={auth ? 'good' : 'bad'} onClick={() => act('auth')}>
              {auth ? '++++++++++' : '----------'}
            </Button>
          </LabeledList.Item>
          <LabeledList.Item label="Status">
            <Box inline bold>
              {status_label}
            </Box>
          </LabeledList.Item>
          <LabeledList.Item label="Timer">
            <Box inline bold mr={1}>
              {timeleft}s
            </Box>
            <Button
              disabled={!canControl}
              color={timing ? 'bad' : 'good'}
              onClick={() => act('timer')}
            >
              {timing ? 'On' : 'Off'}
            </Button>
          </LabeledList.Item>
          <LabeledList.Item label="Time">
            {[-10, -1].map((d) => (
              <Button
                key={d}
                disabled={!canControl}
                onClick={() => act('time', { delta: d })}
              >
                {d}
              </Button>
            ))}
            <Box inline bold mx={1}>
              {timeleft}
            </Box>
            {[1, 10].map((d) => (
              <Button
                key={d}
                disabled={!canControl}
                onClick={() => act('time', { delta: d })}
              >
                +{d}
              </Button>
            ))}
          </LabeledList.Item>
          <LabeledList.Item label="Safety">
            <Button
              disabled={!canControl}
              color={safety ? 'good' : 'bad'}
              onClick={() => act('safety')}
            >
              {safety ? 'On' : 'Off'}
            </Button>
          </LabeledList.Item>
          <LabeledList.Item label="Anchor">
            <Button
              disabled={!canControl}
              color={anchored ? 'good' : 'bad'}
              onClick={() => act('anchor')}
            >
              {anchored ? 'Engaged' : 'Off'}
            </Button>
          </LabeledList.Item>
        </LabeledList>
      </Section>

      <Section title="Keypad">
        <Box mb={1} bold textAlign="center" fontSize="1.4em">
          &gt; {code_display}
        </Box>
        <Stack vertical>
          {KEYPAD.map((row) => (
            <Stack.Item key={row.join('')}>
              <Stack justify="center">
                {row.map((k) => (
                  <Stack.Item key={k}>
                    <Button
                      width="50px"
                      textAlign="center"
                      onClick={() => act('type', { key: k })}
                    >
                      {k}
                    </Button>
                  </Stack.Item>
                ))}
              </Stack>
            </Stack.Item>
          ))}
        </Stack>
      </Section>
    </>
  );
};

const WireView = () => {
  const { data, act } = useBackend<Data>();
  const { wires, timing, safety, lighthack } = data;
  return (
    <>
      <Section title="Bomb Defusion">
        <Stack vertical>
          {wires.map((w) => (
            <Stack.Item key={w.name}>
              <Box inline bold mr={1}>
                {w.name}
              </Box>
              <Button
                color={w.cut ? 'good' : 'bad'}
                onClick={() => act('wire', { wire: w.name })}
              >
                {w.cut ? 'Mend' : 'Cut'}
              </Button>{' '}
              <Button
                disabled={!!w.cut}
                onClick={() => act('pulse', { wire: w.name })}
              >
                Pulse
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      </Section>
      <Section title="Tells">
        <LabeledList>
          <LabeledList.Item label="Device">
            <Box color={timing ? 'bad' : 'good'}>
              {timing ? 'shaking!' : 'still'}
            </Box>
          </LabeledList.Item>
          <LabeledList.Item label="Sound">
            <Box color={safety ? 'good' : 'bad'}>
              {safety ? 'quiet' : 'whirring'}
            </Box>
          </LabeledList.Item>
          <LabeledList.Item label="Lights">
            <Box color={lighthack ? 'bad' : 'good'}>
              {lighthack ? 'static' : 'functional'}
            </Box>
          </LabeledList.Item>
        </LabeledList>
      </Section>
    </>
  );
};
