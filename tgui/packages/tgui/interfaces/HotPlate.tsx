import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  NumberInput,
  Section,
  Table,
} from 'tgui-core/components';
import type { HotPlateActions, HotPlateData } from './generated/HotPlate';

/** The hot plate: the container's temperature, the dial, the element and what in the container boils. */
export function HotPlate() {
  const { act, data } = useBackend<HotPlateData, HotPlateActions>();
  const {
    has_container,
    container_name,
    temperature,
    nested_name,
    nested_temperature,
    target,
    min_target,
    max_target,
    heating,
    powered,
    reagents,
  } = data;

  return (
    <Window width={360} height={380}>
      <Window.Content scrollable>
        <Section
          title="Plate"
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
            <LabeledList.Item label="Element">
              <Box color={heating ? 'orange' : 'label'}>
                {!powered ? 'No power' : heating ? 'Heating' : 'Off'}
              </Box>
            </LabeledList.Item>
          </LabeledList>
        </Section>
        <Section
          title={has_container ? container_name : 'No container'}
          buttons={
            !!has_container && (
              <Button icon="eject" onClick={() => act('remove')}>
                Take off
              </Button>
            )
          }
        >
          {!!has_container && (
            <LabeledList>
              <LabeledList.Item label="Temperature">
                {temperature} C
              </LabeledList.Item>
              {!!nested_name && (
                <LabeledList.Item label={nested_name}>
                  {nested_temperature} C
                </LabeledList.Item>
              )}
            </LabeledList>
          )}
          {!!has_container && reagents.length > 0 && (
            <Table mt={1}>
              <Table.Row header>
                <Table.Cell>Contents</Table.Cell>
                <Table.Cell collapsing>Units</Table.Cell>
                <Table.Cell collapsing>Boils at</Table.Cell>
                <Table.Cell collapsing />
              </Table.Row>
              {reagents.map((reagent) => (
                <Table.Row key={reagent.name}>
                  <Table.Cell>{reagent.name}</Table.Cell>
                  <Table.Cell collapsing>{reagent.volume}</Table.Cell>
                  <Table.Cell collapsing>{reagent.boiling_point} C</Table.Cell>
                  <Table.Cell collapsing>
                    <Box color={reagent.boiling ? 'orange' : 'label'}>
                      {reagent.boiling ? 'Boiling' : '-'}
                    </Box>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
}
