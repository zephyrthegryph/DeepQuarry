// Mecha syringe gun reagent synthesizer — TGUI.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type KnownReagent = {
  id: string;
  name: string;
  selected: BooleanLike;
};

type CurrentReagent = {
  id: string;
  name: string;
  volume: number;
};

type Data = {
  total_volume: number;
  max_volume: number;
  synth_speed: number;
  known_reagents: KnownReagent[];
  current_reagents: CurrentReagent[];
};

export const MechaSyringeGun = () => {
  const { data, act } = useBackend<Data>();
  const [pending, setPending] = useState<Record<string, boolean>>({});
  const isSelected = (r: KnownReagent): boolean =>
    r.id in pending ? pending[r.id] : !!r.selected;
  return (
    <Window width={460} height={520} title="Reagent Synthesizer">
      <Window.Content scrollable>
        <Section title="Current reagents">
          {data.current_reagents.length === 0 ? (
            <EmptyState>None.</EmptyState>
          ) : (
            <>
              <Stack vertical>
                {data.current_reagents.map((r) => (
                  <Stack.Item key={r.id}>
                    <Button
                      color="bad"
                      onClick={() => act('purge_reagent', { id: r.id })}
                    >
                      Purge
                    </Button>{' '}
                    {r.name}: {r.volume}
                  </Stack.Item>
                ))}
              </Stack>
              <Box mt={1}>
                <Box inline bold>
                  Total:
                </Box>{' '}
                {data.total_volume} / {data.max_volume}{' '}
                <Button color="bad" onClick={() => act('purge_all')}>
                  Purge All
                </Button>
              </Box>
            </>
          )}
        </Section>
        <Section
          title="Production"
          buttons={
            <Button
              color="good"
              onClick={() => {
                const selected = data.known_reagents
                  .filter(isSelected)
                  .map((r) => r.id);
                act('select_reagents', { reagents: selected });
              }}
            >
              Apply
            </Button>
          }
        >
          {data.known_reagents.length === 0 ? (
            <EmptyState>No known reagents.</EmptyState>
          ) : (
            <Stack vertical>
              {data.known_reagents.map((r) => {
                const on = isSelected(r);
                return (
                  <Stack.Item key={r.id}>
                    <Button
                      selected={on}
                      onClick={() => setPending({ ...pending, [r.id]: !on })}
                    >
                      {on ? '✓' : '☐'}
                    </Button>{' '}
                    {r.name}
                  </Stack.Item>
                );
              })}
            </Stack>
          )}
          <Box mt={1} italic color="label" fontSize="0.85em">
            Only the first {data.synth_speed} selected reagents will be added to
            production.
          </Box>
        </Section>
      </Window.Content>
    </Window>
  );
};
