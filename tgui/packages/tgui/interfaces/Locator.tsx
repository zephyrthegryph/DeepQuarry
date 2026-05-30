// Persistent signal locator — TGUI.
//
// Tune frequency, click refresh to scan for tracker beacons and
// implants on the same z-level.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Signal = {
  id: string;
  direction: string;
  strength: string;
};

type Data = {
  frequency: string;
  has_scan: BooleanLike;
  location: string;
  beacons: Signal[];
  implants: Signal[];
};

const strengthColor = (s: string): string => {
  if (s === 'very strong') return 'good';
  if (s === 'strong') return 'good';
  if (s === 'weak') return 'average';
  return 'bad';
};

export const Locator = () => {
  const { data, act } = useBackend<Data>();
  const { frequency, has_scan, location, beacons, implants } = data;

  return (
    <Window width={420} height={420}>
      <Window.Content scrollable>
        <Section
          title="Persistent Signal Locator"
          buttons={
            <Button icon="sync" color="good" onClick={() => act('refresh')}>
              Refresh
            </Button>
          }
        >
          <LabeledList>
            <LabeledList.Item label="Frequency">
              <Button onClick={() => act('freq', { delta: -10 })}>-10</Button>{' '}
              <Button onClick={() => act('freq', { delta: -2 })}>-2</Button>{' '}
              <Box inline bold mx={1}>
                {frequency}
              </Box>
              <Button onClick={() => act('freq', { delta: 2 })}>+2</Button>{' '}
              <Button onClick={() => act('freq', { delta: 10 })}>+10</Button>
            </LabeledList.Item>
          </LabeledList>
        </Section>

        {has_scan ? (
          <Section
            title="Last Scan"
            buttons={<Button onClick={() => act('clear')}>Clear</Button>}
          >
            <Box mb={1} color="label">
              Position: {location}
            </Box>
            <Box bold>Located Beacons</Box>
            {beacons.length > 0 ? (
              <Stack vertical>
                {beacons.map((b) => (
                  <Stack.Item key={b.id}>
                    <Box inline bold>
                      {b.id}
                    </Box>{' '}
                    <Box inline color="label">
                      {b.direction}
                    </Box>{' '}
                    <Box inline color={strengthColor(b.strength)}>
                      {b.strength}
                    </Box>
                  </Stack.Item>
                ))}
              </Stack>
            ) : (
              <Box color="label" italic>
                None
              </Box>
            )}
            <Box bold mt={1}>
              Extraneous Signals
            </Box>
            {implants.length > 0 ? (
              <Stack vertical>
                {implants.map((b) => (
                  <Stack.Item key={b.id}>
                    <Box inline bold>
                      {b.id}
                    </Box>{' '}
                    <Box inline color="label">
                      {b.direction}
                    </Box>{' '}
                    <Box inline color={strengthColor(b.strength)}>
                      {b.strength}
                    </Box>
                  </Stack.Item>
                ))}
              </Stack>
            ) : (
              <Box color="label" italic>
                None
              </Box>
            )}
          </Section>
        ) : null}
      </Window.Content>
    </Window>
  );
};
