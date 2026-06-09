// Gravity generator control — TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type AreaStatus = {
  name: string;
  has_gravity: BooleanLike;
  fed_by_us: BooleanLike;
};

type Data = {
  has_generator: BooleanLike;
  generator_on: BooleanLike;
  areas: AreaStatus[];
};

export const GravityGeneratorControl = () => {
  const { data, act } = useBackend<Data>();
  const { has_generator, generator_on, areas } = data;

  return (
    <Window width={420} height={460}>
      <Window.Content scrollable>
        <Section title="Generator Control System">
          {!has_generator ? (
            <Box italic color="bad">
              No local gravity generator detected!
            </Box>
          ) : (
            <>
              <Box mb={1}>
                Gravity Status:{' '}
                <Box inline bold color={generator_on ? 'good' : 'bad'}>
                  {generator_on ? 'ON' : 'OFF'}
                </Box>
              </Box>
              <Section title="Coverage">
                <Stack vertical>
                  {areas.map((a) => (
                    <Stack.Item key={a.name}>
                      <Box
                        color={
                          a.has_gravity && a.fed_by_us
                            ? 'good'
                            : a.has_gravity
                              ? 'average'
                              : 'bad'
                        }
                      >
                        {a.name}
                      </Box>
                    </Stack.Item>
                  ))}
                </Stack>
              </Section>
              <Box mt={1}>
                <Button
                  fluid
                  color={generator_on ? 'bad' : 'good'}
                  onClick={() => act('toggle')}
                >
                  Turn gravity generator {generator_on ? 'OFF' : 'ON'}
                </Button>
              </Box>
            </>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
