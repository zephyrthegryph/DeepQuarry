// Integrated-electronics list pin editor — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Entry = {
  pos: number;
  display: string;
};

type Data = {
  name: string;
  length: number;
  entries: Entry[];
};

export const ListPin = () => {
  const { data, act } = useBackend<Data>();
  const { name, length, entries } = data;
  return (
    <Window width={520} height={520} title={`List Pin: ${name}`}>
      <Window.Content scrollable>
        <Section
          title={`${name} (length ${length})`}
          buttons={
            <>
              <Button onClick={() => act('refresh')} icon="rotate-right">
                Refresh
              </Button>{' '}
              <Button onClick={() => act('add')} icon="plus">
                Add
              </Button>{' '}
              <Button onClick={() => act('swap')} icon="right-left">
                Swap
              </Button>{' '}
              <Button color="bad" onClick={() => act('clear')} icon="trash">
                Clear
              </Button>
            </>
          }
        >
          {entries.length === 0 ? (
            <EmptyState>(empty)</EmptyState>
          ) : (
            <Stack vertical>
              {entries.map((e) => (
                <Stack.Item key={e.pos}>
                  <Stack>
                    <Stack.Item grow>
                      <Box>
                        <b>#{e.pos}</b> {e.display}
                      </Box>
                    </Stack.Item>
                    <Stack.Item>
                      <Button
                        compact
                        onClick={() => act('edit', { pos: e.pos })}
                      >
                        Edit
                      </Button>{' '}
                      <Button
                        compact
                        color="bad"
                        onClick={() => act('remove', { pos: e.pos })}
                      >
                        Remove
                      </Button>
                    </Stack.Item>
                  </Stack>
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
