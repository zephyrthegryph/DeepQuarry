import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  NoticeBox,
  Section,
} from 'tgui-core/components';
import type {
  PortableGeneratorActions,
  PortableGeneratorData,
} from './generated/PortableGenerator';
import { StatBar } from 'tgui/components/StatBar';

type Data = PortableGeneratorData;

export const PortableGenerator = (props) => {
  const { act, data } = useBackend<Data, PortableGeneratorActions>();

  const {
    fuel_stored,
    fuel_capacity,
    anchored,
    active,
    ready_to_boot,
    sheet_name,
    fuel_usage,
    temperature_current,
    temperature_max,
    temperature_overheat,
    unsafe_output,
    power_output,
    power_generated,
    connected,
    power_available,
  } = data;

  const stack_percent: number = fuel_stored / fuel_capacity;
  const stackPercentState: string =
    (stack_percent >= 0.5 && 'good') ||
    (stack_percent > 0.15 && 'average') ||
    'bad';
  return (
    <Window width={450} height={340}>
      <Window.Content scrollable>
        {!anchored && <NoticeBox>Generator not anchored.</NoticeBox>}
        <Section title="Status">
          <LabeledList>
            <LabeledList.Item label="Power switch">
              <Button
                icon={active ? 'power-off' : 'times'}
                onClick={() => act('toggle_power')}
                selected={active}
                disabled={!ready_to_boot}
              >
                {active ? 'On' : 'Off'}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item
              label="Fuel Type"
              buttons={
                fuel_stored >= 1 && (
                  <Button
                    ml={1}
                    icon="eject"
                    disabled={active}
                    onClick={() => act('eject')}
                  >
                    Eject
                  </Button>
                )
              }
            >
              <Box color={stackPercentState}>
                {fuel_stored}cm&sup3; {sheet_name}
              </Box>
            </LabeledList.Item>
            <StatBar
              label="Current fuel level"
              value={fuel_stored / fuel_capacity}
              ranges={{
                good: [0.5, Infinity],
                average: [0.15, 0.5],
                bad: [-Infinity, 0.15],
              }}
            >
              {fuel_stored}cm&sup3; / {fuel_capacity}cm&sup3;
            </StatBar>
            <LabeledList.Item label="Fuel Usage">
              {fuel_usage} cm&sup3;/s
            </LabeledList.Item>
            <StatBar
              label="Temperature"
              value={temperature_current}
              maxValue={temperature_max + 30}
              color={temperature_overheat ? 'bad' : 'good'}
            >
              {(temperature_current ?? 0).toFixed()}&deg;C
            </StatBar>
          </LabeledList>
        </Section>
        <Section title="Output">
          <LabeledList>
            <LabeledList.Item
              label="Current output"
              color={unsafe_output ? 'bad' : undefined}
            >
              {power_output}
            </LabeledList.Item>
            <LabeledList.Item label="Adjust output">
              <Button icon="minus" onClick={() => act('lower_power')}>
                {power_generated}
              </Button>
              <Button icon="plus" onClick={() => act('higher_power')}>
                {power_generated}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Power available">
              <Box inline color={!connected && 'bad'}>
                {connected ? power_available : 'Unconnected'}
              </Box>
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
