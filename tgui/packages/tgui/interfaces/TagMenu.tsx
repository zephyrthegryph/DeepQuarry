// Admin Tag Menu — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';
import type { TagMenuActions, TagMenuData } from './generated/TagMenu';
import { Label } from 'tgui/components/Label';

export const TagMenu = () => {
  const { data, act } = useBackend<TagMenuData, TagMenuActions>();
  const { entries = [] } = data;
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
                    <Label inline>({e.type})</Label>
                  </Box>
                  {e.area_coord ? (
                    <Label ml={1}>
                      {e.area_coord}
                      {e.health ? ` — ${e.health}` : ''}
                    </Label>
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
