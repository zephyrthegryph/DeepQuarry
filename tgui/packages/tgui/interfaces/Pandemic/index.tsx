import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Stack } from 'tgui-core/components';
import type { PandemicActions, PandemicData } from '../generated/Pandemic';
import { BeakerDisplay } from './Beaker';
import { SpecimenDisplay } from './Specimen';

export const Pandemic = (props) => {
  const { data } = useBackend<PandemicData, PandemicActions>();
  const { has_beaker, has_blood } = data;

  return (
    <Window width={650} height={510}>
      <Window.Content>
        <Stack fill vertical>
          <Stack.Item>
            <BeakerDisplay />
          </Stack.Item>
          {!!has_beaker && !!has_blood && (
            <Stack.Item grow>
              <SpecimenDisplay />
            </Stack.Item>
          )}
        </Stack>
      </Window.Content>
    </Window>
  );
};
