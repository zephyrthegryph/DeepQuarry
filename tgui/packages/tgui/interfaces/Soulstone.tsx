// Soulstone — TGUI.
//
// Shows captured shade (if any). Single action: summon.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Data = {
  has_shade: BooleanLike;
  shade_name: string;
};

export const Soulstone = () => {
  const { data, act } = useBackend<Data>();
  const { has_shade, shade_name } = data;

  return (
    <Window width={320} height={180}>
      <Window.Content>
        <Section title="Soul Stone">
          {has_shade ? (
            <>
              <Box mb={1}>
                Captured soul:{' '}
                <Box inline bold>
                  {shade_name}
                </Box>
              </Box>
              <Button
                fluid
                icon="ghost"
                color="bad"
                onClick={() => act('summon')}
              >
                Summon Shade
              </Button>
            </>
          ) : (
            <EmptyState>The stone is empty.</EmptyState>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
