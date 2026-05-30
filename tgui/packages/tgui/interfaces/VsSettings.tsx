// ZAS / Phoron Variable Settings — structured TGUI for admin tuning.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Entry = {
  key: string;
  name: string;
  value: string;
  description: string;
};

type Data = {
  entries: Entry[];
};

export const VsSettings = () => {
  const { data, act } = useBackend<Data>();
  const { entries } = data;
  return (
    <Window width={640} height={620} title="Variable Settings">
      <Window.Content scrollable>
        <Section title="Variable Settings">
          {entries.length === 0 ? (
            <EmptyState>(no settings)</EmptyState>
          ) : (
            <Stack vertical>
              {entries.map((e) => (
                <Stack.Item key={e.key}>
                  <Box>
                    <Box inline bold>
                      {e.name}
                    </Box>{' '}
                    = <Box inline>{e.value}</Box>{' '}
                    <Button
                      compact
                      onClick={() => act('change', { key: e.key })}
                    >
                      Change
                    </Button>
                  </Box>
                  <Box ml={1} italic color="label">
                    {e.description}
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
