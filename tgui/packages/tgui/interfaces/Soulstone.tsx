// Soulstone — TGUI.
//
// Shows captured shade (if any). Single action: summon.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';
import type { SoulstoneActions, SoulstoneData } from './generated/Soulstone';

export const Soulstone = () => {
  const { data, act } = useBackend<SoulstoneData, SoulstoneActions>();
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
