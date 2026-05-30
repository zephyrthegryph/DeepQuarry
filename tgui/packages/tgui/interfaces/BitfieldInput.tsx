// Bitfield editor — TGUI.
//
// Replaces the legacy /datum/browser/modal/list_picker UI that
// input_bitfield() used to render. Each flag is a toggle row; read-only
// flags appear but their toggle is disabled.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Flag = {
  name: string;
  bit: number;
  checked: BooleanLike;
  editable: BooleanLike;
};

type Data = {
  title: string;
  flags: Flag[];
};

export const BitfieldInput = () => {
  const { data, act } = useBackend<Data>();
  const { title, flags } = data;
  return (
    <Window width={420} height={520} title={title}>
      <Window.Content scrollable>
        <Section title={title}>
          <Stack vertical>
            {flags.map((flag) => (
              <Stack.Item key={flag.bit}>
                <Button
                  fluid
                  selected={!!flag.checked}
                  disabled={!flag.editable}
                  icon={flag.checked ? 'check-square-o' : 'square-o'}
                  onClick={() => act('toggle', { bit: flag.bit })}
                >
                  {flag.name}
                </Button>
              </Stack.Item>
            ))}
          </Stack>
        </Section>
        <Section>
          <Box>
            <Button color="good" onClick={() => act('submit')}>
              Save
            </Button>{' '}
            <Button onClick={() => act('cancel')}>Cancel</Button>
          </Box>
        </Section>
      </Window.Content>
    </Window>
  );
};
