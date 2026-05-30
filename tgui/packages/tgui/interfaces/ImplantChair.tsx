// Implant chair — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Data = {
  has_occupant: BooleanLike;
  occupant_name?: string;
  health_text?: string;
  dead?: BooleanLike;
  damaged?: BooleanLike;
  implants_left: number;
  ready: BooleanLike;
};

export const ImplantChair = () => {
  const { data, act } = useBackend<Data>();
  const {
    has_occupant,
    occupant_name,
    health_text,
    dead,
    damaged,
    implants_left,
    ready,
  } = data;
  return (
    <Window width={420} height={300} title="Implanter Status">
      <Window.Content>
        <Section title="Implanter Status">
          <LabeledList>
            <LabeledList.Item label="Current occupant">
              {has_occupant ? (
                <>
                  <Box>{occupant_name}</Box>
                  <Box color={dead || damaged ? 'bad' : undefined}>
                    Health: {dead ? 'Dead' : health_text}
                  </Box>
                </>
              ) : (
                <Box color="bad">None</Box>
              )}
            </LabeledList.Item>
            <LabeledList.Item label="Implants">
              {implants_left > 0 ? (
                implants_left
              ) : (
                <Button onClick={() => act('replenish')}>Replenish</Button>
              )}
            </LabeledList.Item>
          </LabeledList>
          {has_occupant ? (
            <Box mt={2}>
              {ready ? (
                <Button
                  icon="syringe"
                  color="good"
                  onClick={() => act('implant')}
                >
                  Implant
                </Button>
              ) : (
                <EmptyState>Recharging…</EmptyState>
              )}
            </Box>
          ) : null}
        </Section>
      </Window.Content>
    </Window>
  );
};
