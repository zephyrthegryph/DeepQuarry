// Vending machine log — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';
import { Label } from 'tgui/components/Label';

type Entry = string[]; // [time, action, registered_name, stationtime, item_name]

type Data = {
  machine_name: string;
  user_name: string;
  entries: Entry[];
};

export const VendingLog = () => {
  const { data } = useBackend<Data>();
  const { machine_name, user_name, entries = [] } = data;
  return (
    <Window width={680} height={620} title={`${machine_name} Vending Log`}>
      <Window.Content scrollable>
        <Section
          title={`${machine_name} Vending Log`}
          buttons={<EmptyState>Welcome, {user_name}</EmptyState>}
        >
          {entries.length === 0 ? (
            <EmptyState>No entries.</EmptyState>
          ) : (
            <Stack vertical>
              {entries.map((e, i) => (
                <Stack.Item key={i}>
                  <Box>
                    <Box inline bold>
                      [{e[2]}]
                    </Box>{' '}
                    <Box inline color={e[1] === 'vend' ? 'good' : 'average'}>
                      {e[1]}
                    </Box>{' '}
                    — <Box inline>{e[4]}</Box> <Label inline>@ {e[3]}</Label>
                  </Box>
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
