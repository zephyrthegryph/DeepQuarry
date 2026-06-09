// Admin Tag Menu — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Entry = {
  index: number;
  ref: string;
  name: string;
  type: string;
  area_coord: string;
  health: string;
  is_marked: BooleanLike;
};

type Data = {
  entries: Entry[];
};

export const TagMenu = () => {
  const { data, act } = useBackend<Data>();
  const { entries } = data;
  return (
    <Window width={620} height={620} title="Tag Menu">
      <Window.Content scrollable>
        <Section
          title="Tagged Datums"
          buttons={
            <Button onClick={() => act('refresh')} icon="rotate-right">
              Refresh
            </Button>
          }
        >
          {entries.length === 0 ? (
            <EmptyState>No datums tagged.</EmptyState>
          ) : (
            <Stack vertical>
              {entries.map((e) => (
                <Stack.Item key={e.ref}>
                  <Box>
                    <Box bold inline>
                      #{e.index}: {e.name}
                    </Box>{' '}
                    <Box color="label" inline>
                      ({e.type})
                    </Box>
                  </Box>
                  {e.area_coord ? (
                    <Box ml={1} color="label">
                      {e.area_coord}
                      {e.health ? ` — ${e.health}` : ''}
                    </Box>
                  ) : null}
                  <Box mt="2px">
                    <Button compact onClick={() => act('vv', { ref: e.ref })}>
                      VV
                    </Button>{' '}
                    <Button compact onClick={() => act('pp', { ref: e.ref })}>
                      PP
                    </Button>{' '}
                    <Button
                      compact
                      onClick={() => act('follow', { ref: e.ref })}
                    >
                      Follow
                    </Button>{' '}
                    <Button
                      compact
                      color="bad"
                      onClick={() => act('untag', { ref: e.ref })}
                    >
                      Untag
                    </Button>{' '}
                    {e.is_marked ? (
                      <Box inline bold>
                        Marked
                      </Box>
                    ) : (
                      <Button
                        compact
                        onClick={() => act('mark', { ref: e.ref })}
                      >
                        Mark
                      </Button>
                    )}
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
