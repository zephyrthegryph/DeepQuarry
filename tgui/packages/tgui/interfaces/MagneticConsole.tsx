// Magnetic Control Console — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Magnet = {
  index: number;
  ref: string;
  on: BooleanLike;
  electricity_level: number;
  magnetic_field: number;
};

type Data = {
  autolink: BooleanLike;
  frequency: number;
  code: number;
  speed: number;
  path: string;
  moving: BooleanLike;
  magnets: Magnet[];
};

export const MagneticConsole = () => {
  const { data, act } = useBackend<Data>();
  const { autolink, frequency, code, speed, path, moving, magnets } = data;
  return (
    <Window width={520} height={520} title="Magnetic Control Console">
      <Window.Content scrollable>
        {!autolink ? (
          <Section title="Radio">
            <LabeledList>
              <LabeledList.Item label="Frequency">
                <Button onClick={() => act('set_frequency')}>
                  {frequency}
                </Button>
              </LabeledList.Item>
              <LabeledList.Item label="Code">
                <Button onClick={() => act('set_code')}>{code}</Button>
              </LabeledList.Item>
              <LabeledList.Item label="Probe">
                <Button icon="search" onClick={() => act('probe')}>
                  Probe Generators
                </Button>
              </LabeledList.Item>
            </LabeledList>
          </Section>
        ) : null}

        {magnets.length > 0 ? (
          <Section title="Magnets confirmed">
            <Stack vertical>
              {magnets.map((m) => (
                <Stack.Item key={m.ref}>
                  <Stack>
                    <Stack.Item width="36px" color="label">
                      [{m.index}]
                    </Stack.Item>
                    <Stack.Item>
                      <Button
                        selected={!!m.on}
                        icon="power-off"
                        onClick={() => act('toggle_power')}
                      >
                        {m.on ? 'On' : 'Off'}
                      </Button>
                    </Stack.Item>
                    <Stack.Item color="label">Electricity:</Stack.Item>
                    <Stack.Item>
                      <Button onClick={() => act('elec_minus')}>−</Button>
                      <Box inline bold mx={1}>
                        {m.electricity_level}
                      </Box>
                      <Button onClick={() => act('elec_plus')}>+</Button>
                    </Stack.Item>
                    <Stack.Item color="label">Field:</Stack.Item>
                    <Stack.Item>
                      <Button onClick={() => act('mag_minus')}>−</Button>
                      <Box inline bold mx={1}>
                        {m.magnetic_field}
                      </Box>
                      <Button onClick={() => act('mag_plus')}>+</Button>
                    </Stack.Item>
                  </Stack>
                </Stack.Item>
              ))}
            </Stack>
          </Section>
        ) : (
          <Section>
            <EmptyState>No magnets connected.</EmptyState>
          </Section>
        )}

        <Section title="Sequence">
          <LabeledList>
            <LabeledList.Item label="Speed">
              <Button onClick={() => act('speed_minus')}>−</Button>
              <Box inline bold mx={1}>
                {speed}
              </Box>
              <Button onClick={() => act('speed_plus')}>+</Button>
            </LabeledList.Item>
            <LabeledList.Item label="Path">
              <Button onClick={() => act('set_path')}>
                {path || '(empty)'}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Moving">
              <Button selected={!!moving} onClick={() => act('toggle_moving')}>
                {moving ? 'Enabled' : 'Disabled'}
              </Button>
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
