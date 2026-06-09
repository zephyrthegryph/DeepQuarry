// Airlock electronics — TGUI.
//
// Unlock with an ID, then toggle ANY/ALL gating and tick the access flags
// the airlock should require.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type AccessOption = {
  id: number;
  name: string;
  selected: BooleanLike;
};

type Data = {
  locked: BooleanLike;
  one_access: BooleanLike;
  last_configurator: string;
  all_selected: BooleanLike;
  accesses: AccessOption[];
};

export const AirlockElectronics = () => {
  const { data, act } = useBackend<Data>();
  const { locked, one_access, last_configurator, all_selected, accesses } =
    data;

  return (
    <Window width={440} height={520}>
      <Window.Content scrollable>
        <Section
          title="Access control"
          buttons={
            <Button
              icon={locked ? 'lock' : 'lock-open'}
              color={locked ? 'good' : 'bad'}
              onClick={() => act(locked ? 'login' : 'logout')}
            >
              {locked ? 'Unlock' : 'Lock'} Interface
            </Button>
          }
        >
          {last_configurator ? (
            <LabeledList>
              <LabeledList.Item label="Operator">
                {last_configurator}
              </LabeledList.Item>
            </LabeledList>
          ) : null}

          {locked ? (
            <Box mt={1} italic color="label">
              Unlock the interface to configure access requirements.
            </Box>
          ) : (
            <Box mt={1}>
              <LabeledList>
                <LabeledList.Item label="Requirement">
                  <Button
                    color={one_access ? 'good' : 'bad'}
                    onClick={() => act('one_access')}
                  >
                    {one_access ? 'ONE of the selected' : 'ALL selected'}
                  </Button>
                </LabeledList.Item>
                <LabeledList.Item label="Quick">
                  <Button
                    color={all_selected ? 'bad' : 'default'}
                    onClick={() => act('access', { access: 'all' })}
                  >
                    {all_selected ? 'All (clear selection)' : 'All'}
                  </Button>
                </LabeledList.Item>
              </LabeledList>

              <Stack vertical mt={2}>
                {accesses.map((a) => (
                  <Stack.Item key={a.id}>
                    <Button
                      fluid
                      color={
                        a.selected ? (one_access ? 'good' : 'bad') : 'default'
                      }
                      onClick={() => act('access', { access: String(a.id) })}
                    >
                      {a.name}
                    </Button>
                  </Stack.Item>
                ))}
              </Stack>
            </Box>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
