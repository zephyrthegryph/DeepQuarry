// Airlock electronics — TGUI.
//
// Unlock with an ID, then toggle ANY/ALL gating and tick the access flags
// the airlock should require.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type {
  AirlockElectronicsActions,
  AirlockElectronicsData,
} from './generated/AirlockElectronics';
import { Label } from 'tgui/components/Label';

export const AirlockElectronics = () => {
  const { data, act } = useBackend<
    AirlockElectronicsData,
    AirlockElectronicsActions
  >();
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
          <LabeledList>
            {last_configurator ? (
              <LabeledList.Item label="Operator">
                {last_configurator}
              </LabeledList.Item>
            ) : null}
            {locked ? null : (
              <>
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
                    onClick={() => act('access_all')}
                  >
                    {all_selected ? 'All (clear selection)' : 'All'}
                  </Button>
                </LabeledList.Item>
              </>
            )}
          </LabeledList>

          {locked ? (
            <Label mt={1} italic>
              Unlock the interface to configure access requirements.
            </Label>
          ) : (
            <Stack vertical mt={2}>
              {accesses.map((a) => (
                <Stack.Item key={a.id}>
                  <Button
                    fluid
                    color={
                      a.selected ? (one_access ? 'good' : 'bad') : 'default'
                    }
                    onClick={() => act('access', { access: a.id })}
                  >
                    {a.name}
                  </Button>
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
