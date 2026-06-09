// Exosuit internal log — TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Entry = {
  time: string;
  message: string;
};

type Data = {
  title: string;
  entries: Entry[];
};

export const MechaLog = () => {
  const { data } = useBackend<Data>();
  return (
    <Window width={520} height={520} title={data.title}>
      <Window.Content scrollable>
        <Section>
          {data.entries.length === 0 ? (
            <EmptyState>No entries.</EmptyState>
          ) : (
            <Stack vertical>
              {data.entries.map((e, i) => (
                <Stack.Item key={i}>
                  <Box bold>{e.time}</Box>
                  <Box ml={2}>{e.message}</Box>
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
