// Clipboard — TGUI.
//
// Like Folder, plus a pen slot and a designated top paper that can be
// written on directly. Read/rename/look/remove chain to the contained
// items' legacy browse() views since paper/photo are not yet TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Kind = 'paper' | 'photo';

type Item = {
  ref: string;
  name: string;
  kind: Kind;
  is_top: BooleanLike;
};

type Data = {
  has_pen: BooleanLike;
  items: Item[];
};

export const Clipboard = () => {
  const { data, act } = useBackend<Data>();
  const { has_pen, items } = data;

  return (
    <Window width={480} height={440} title="Clipboard">
      <Window.Content scrollable>
        <Section
          title="Pen"
          buttons={
            <Button
              icon={has_pen ? 'minus' : 'plus'}
              color={has_pen ? 'bad' : 'good'}
              onClick={() => act(has_pen ? 'remove_pen' : 'add_pen')}
            >
              {has_pen ? 'Remove Pen' : 'Add Pen'}
            </Button>
          }
        />

        <Section title="Contents">
          {items.length === 0 ? (
            <EmptyState>Empty.</EmptyState>
          ) : (
            <Stack vertical>
              {items.map((i) => (
                <Stack.Item key={i.ref}>
                  {i.is_top && i.kind === 'paper' && !!has_pen ? (
                    <Button
                      color="good"
                      onClick={() => act('write', { ref: i.ref })}
                    >
                      Write
                    </Button>
                  ) : null}{' '}
                  <Button
                    onClick={() => act('open', { ref: i.ref, kind: i.kind })}
                  >
                    {i.kind === 'photo' ? 'Look' : 'Read'}
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
                  {i.is_top ? (
                    <Box inline bold ml={1}>
                      {i.name} (top)
                    </Box>
                  ) : (
                    <Box inline ml={1}>
                      {i.name}
                    </Box>
                  )}
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
