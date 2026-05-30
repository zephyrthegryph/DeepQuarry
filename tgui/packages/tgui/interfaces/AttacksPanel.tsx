// Known Attacks — structured TGUI for default-attack selection.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Attack = {
  ref: string;
  name: string;
  is_default: BooleanLike;
};

type Data = {
  default_name: string | null;
  attacks: Attack[];
};

export const AttacksPanel = () => {
  const { data, act } = useBackend<Data>();
  const { default_name, attacks } = data;
  return (
    <Window width={460} height={400} title="Known Attacks">
      <Window.Content scrollable>
        <Section title="Default Attack">
          {default_name ? (
            <>
              <Box mb={1}>
                Current default:{' '}
                <Box inline bold>
                  {default_name}
                </Box>
              </Box>
              <Button onClick={() => act('reset_default')} icon="rotate-right">
                Reset
              </Button>
            </>
          ) : (
            <EmptyState>No default attack set.</EmptyState>
          )}
        </Section>
        <Section title="Attacks">
          <Stack vertical>
            {attacks.map((a) => (
              <Stack.Item key={a.ref}>
                <Box>
                  <Box inline bold>
                    Primarily {a.name}
                  </Box>{' '}
                  {a.is_default ? (
                    <Box inline color="good">
                      default
                    </Box>
                  ) : (
                    <Button
                      compact
                      onClick={() => act('set_default', { ref: a.ref })}
                    >
                      Set Default
                    </Button>
                  )}
                </Box>
              </Stack.Item>
            ))}
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};
