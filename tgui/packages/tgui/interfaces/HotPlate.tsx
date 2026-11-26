import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  NumberInput,
  Section,
} from 'tgui-core/components';
import type { HotPlateActions, HotPlateData } from './generated/HotPlate';

/** The hot plate: the container's temperature, the dial, the element switch and the power. */
export function HotPlate() {
  const { act, data } = useBackend<HotPlateData, HotPlateActions>();
  const { temperature, target, min_target, max_target, heating, powered } =
    data;

  return (
    <Window width={300} height={190}>
      <Window.Content>
        <Section
          title="Hot plate"
          buttons={
            <Button
              icon="power-off"
              selected={heating}
              disabled={!powered && !heating}
              onClick={() => act('toggle')}
            >
              {heating ? 'On' : 'Off'}
            </Button>
          }
        >
          <LabeledList>
            <LabeledList.Item label="Beaker">
              {temperature === null ? 'None' : `${temperature} C`}
            </LabeledList.Item>
            <LabeledList.Item label="Dial">
              <NumberInput
                value={target}
                minValue={min_target}
                maxValue={max_target}
                step={1}
                unit="C"
                width="80px"
                onChange={(value) => act('set_dial', { celsius: value })}
              />
            </LabeledList.Item>
            <LabeledList.Item label="Power">
              <Box color={powered ? 'good' : 'bad'}>
                {powered ? 'Powered' : 'No power'}
              </Box>
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
}
