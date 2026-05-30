// Pacman II portable phoron generator — TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Data = {
  active: BooleanLike;
  has_fuel: BooleanLike;
  fuel: number;
  power_output: number;
  power_gen: number;
  heat: number;
  emagged: BooleanLike;
};

export const Pacman2 = () => {
  const { data, act } = useBackend<Data>();
  const { active, has_fuel, fuel, power_output, power_gen, heat, emagged } =
    data;

  return (
    <Window width={420} height={260}>
      <Window.Content>
        <Section title="P.A.C.M.A.N. II">
          <LabeledList>
            <LabeledList.Item label="Generator">
              <Button
                icon={active ? 'power-off' : 'play'}
                color={active ? 'good' : 'bad'}
                selected={!!active}
                onClick={() => act(active ? 'disable' : 'enable')}
              >
                {active ? 'On' : 'Off'}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Phoron tank">
              {has_fuel ? (
                <Box inline bold>
                  {fuel} u
                </Box>
              ) : (
                <Box inline italic color="bad">
                  No tank loaded
                </Box>
              )}
            </LabeledList.Item>
            <LabeledList.Item label="Power output">
              <Button onClick={() => act('lower_power')}>-</Button>{' '}
              <Box inline bold mx={1}>
                {power_gen * power_output}
              </Box>
              <Button onClick={() => act('higher_power')}>+</Button>
              {emagged ? (
                <Box inline color="bad" ml={1}>
                  (overdriven)
                </Box>
              ) : null}
            </LabeledList.Item>
            <LabeledList.Item label="Heat">
              <Box inline bold color={heat > 50 ? 'bad' : 'good'}>
                {heat}
              </Box>
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
