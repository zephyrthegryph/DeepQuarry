// Game Panel — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Data = {
  master_mode: string;
  secret_mode: BooleanLike;
};

export const GamePanel = () => {
  const { data, act } = useBackend<Data>();
  const { master_mode, secret_mode } = data;
  return (
    <Window width={360} height={360} title="Game Panel">
      <Window.Content>
        <Section title="Mode">
          <LabeledList>
            <LabeledList.Item label="Current mode">
              {master_mode}
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1}>
            <Button icon="exchange" onClick={() => act('change_mode')}>
              Change Game Mode
            </Button>
            {secret_mode ? (
              <Box mt={1}>
                <Button
                  icon="user-secret"
                  color="bad"
                  onClick={() => act('force_secret')}
                >
                  Force Secret Mode
                </Button>
              </Box>
            ) : null}
          </Box>
        </Section>

        <Section title="Spawning">
          <Button icon="plus-circle" onClick={() => act('spawn_panel')}>
            Spawn Panel
          </Button>
        </Section>

        <Section title="ZAS Settings">
          <Stack vertical>
            <Stack.Item>
              <Button onClick={() => act('vsc', { setting: 'airflow' })}>
                Edit Airflow Settings
              </Button>
            </Stack.Item>
            <Stack.Item>
              <Button onClick={() => act('vsc', { setting: 'phoron' })}>
                Edit Phoron Settings
              </Button>
            </Stack.Item>
            <Stack.Item>
              <Button onClick={() => act('vsc', { setting: 'default' })}>
                Choose default ZAS setting
              </Button>
            </Stack.Item>
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};
