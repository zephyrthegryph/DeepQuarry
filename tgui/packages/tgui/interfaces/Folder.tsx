// Folder — TGUI.
//
// Lists the folder's contents (paper, photos, paper bundles). Each item
// can be opened (read/look/browse), renamed, or removed. Opening a paper
// or photo currently chains to the legacy browse() viewer on those
// items; the folder UI itself is TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Kind = 'paper' | 'photo' | 'bundle';

type Item = {
  ref: string;
  name: string;
  kind: Kind;
};

type Data = {
  folder_name: string;
  items: Item[];
};

const openLabel: Record<Kind, string> = {
  paper: 'Read',
  photo: 'Look',
  bundle: 'Browse',
};

export const Folder = () => {
  const { data, act } = useBackend<Data>();
  const { folder_name, items } = data;

  return (
    <Window width={460} height={420} title={folder_name}>
      <Window.Content scrollable>
        <Section title="Contents">
          {items.length === 0 ? (
            <EmptyState>Empty.</EmptyState>
          ) : (
            <Stack vertical>
              {items.map((i) => (
                <Stack.Item key={i.ref}>
                  <Button
                    onClick={() => act('open', { ref: i.ref, kind: i.kind })}
                  >
                    {openLabel[i.kind]}
                  </Button>{' '}
                  <Button onClick={() => act('rename', { ref: i.ref })}>
                    Rename
                  </Button>{' '}
                  <Button
                    color="bad"
                    onClick={() => act('remove', { ref: i.ref })}
                  >
                    Remove
                  </Button>{' '}
                  <Box inline ml={1}>
                    {i.name}
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
