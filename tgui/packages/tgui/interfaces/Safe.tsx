// Combination safe — TGUI.
//
// Two-tumbler dial. Click +/- to rotate, then open/close. When open,
// show the contents list with retrieve buttons.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Content = {
  ref: string;
  name: string;
};

type Data = {
  open: BooleanLike;
  dial: number;
  contents: Content[];
};

export const Safe = () => {
  const { data, act } = useBackend<Data>();
  const { open, dial, contents } = data;

  return (
    <Window width={360} height={360}>
      <Window.Content>
        <Section>
          <Stack align="center" justify="center">
            <Stack.Item>
              <Button icon="minus" onClick={() => act('decrement')} />
            </Stack.Item>
            <Stack.Item width="60px" textAlign="center">
              <Box bold fontSize="1.4em">
                {dial * 5}
              </Box>
            </Stack.Item>
            <Stack.Item>
              <Button icon="plus" onClick={() => act('increment')} />
            </Stack.Item>
            <Stack.Item ml={2}>
              <Button
                icon={open ? 'lock' : 'lock-open'}
                color={open ? 'bad' : 'good'}
                onClick={() => act('open')}
              >
                {open ? 'Close' : 'Open'}
              </Button>
            </Stack.Item>
          </Stack>
        </Section>
        {open && contents.length > 0 ? (
          <Section title="Contents">
            <Stack vertical>
              {contents.map((c) => (
                <Stack.Item key={c.ref}>
                  <Button
                    fluid
                    icon="hand-paper"
                    onClick={() => act('retrieve', { ref: c.ref })}
                  >
                    {c.name}
                  </Button>
                </Stack.Item>
              ))}
            </Stack>
          </Section>
        ) : null}
      </Window.Content>
    </Window>
  );
};
