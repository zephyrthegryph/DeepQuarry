// Dartgun mixing control — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Reagent = {
  name: string;
  volume: number;
};

type Beaker = {
  index: number;
  reagents: Reagent[];
  mixing: BooleanLike;
};

type Data = {
  beakers: Beaker[];
  ammo_count: number | null;
};

export const Dartgun = () => {
  const { data, act } = useBackend<Data>();
  const { beakers, ammo_count } = data;
  return (
    <Window width={460} height={460} title="Dartgun mixing control">
      <Window.Content scrollable>
        <Section title="Beakers">
          {beakers.length === 0 ? (
            <EmptyState>No beakers inserted.</EmptyState>
          ) : (
            <Stack vertical>
              {beakers.map((b) => (
                <Stack.Item key={b.index}>
                  <Box bold>Beaker {b.index}</Box>
                  {b.reagents.length === 0 ? (
                    <Box color="label" italic>
                      empty
                    </Box>
                  ) : (
                    <>
                      <Box ml={1} color="label">
                        {b.reagents
                          .map((r) => `${r.volume}u ${r.name}`)
                          .join(', ')}
                      </Box>
                      <Box mt="2px">
                        <Button
                          compact
                          selected={!!b.mixing}
                          color={b.mixing ? 'good' : 'bad'}
                          onClick={() => act('toggle_mix', { index: b.index })}
                        >
                          {b.mixing ? 'Mixing' : 'Not mixing'}
                        </Button>{' '}
                        <Button
                          compact
                          icon="eject"
                          onClick={() =>
                            act('eject_beaker', { index: b.index })
                          }
                        >
                          Eject
                        </Button>
                      </Box>
                    </>
                  )}
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
        {ammo_count !== null ? (
          <Section title="Dart Cartridge">
            <Box color={ammo_count > 0 ? undefined : 'bad'}>
              {ammo_count > 0
                ? `${ammo_count} shots remaining.`
                : 'The dart cartridge is empty!'}
            </Box>
            <Box mt={1}>
              <Button icon="eject" onClick={() => act('eject_cart')}>
                Eject
              </Button>
            </Box>
          </Section>
        ) : null}
      </Window.Content>
    </Window>
  );
};
