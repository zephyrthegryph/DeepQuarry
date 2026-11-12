import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Button,
  LabeledList,
  NumberInput,
  Section,
  Table,
} from 'tgui-core/components';
import type {
  SolarControlActions,
  SolarControlData,
} from './generated/SolarControl';
import { StatBar } from 'tgui/components/StatBar';
import { Label } from 'tgui/components/Label';

type Data = SolarControlData;

export const SolarControl = (props) => {
  const { act, data } = useBackend<Data, SolarControlActions>();
  const {
    generated,
    generated_ratio,
    sun_angle,
    array_angle,
    rotation_rate,
    max_rotation_rate,
    tracking_state,
    connected_panels,
    connected_tracker,
  } = data;
  return (
    <Window width={380} height={230}>
      <Window.Content>
        <Section
          title="Status"
          buttons={
            <Button icon="sync" onClick={() => act('refresh')}>
              Scan for new hardware
            </Button>
          }
        >
          <Table>
            <Table.Row>
              <Table.Cell>
                <LabeledList>
                  <LabeledList.Item
                    label="Solar tracker"
                    color={connected_tracker ? 'good' : 'bad'}
                  >
                    {connected_tracker ? 'OK' : 'N/A'}
                  </LabeledList.Item>
                  <LabeledList.Item
                    label="Solar panels"
                    color={connected_panels > 0 ? 'good' : 'bad'}
                  >
                    {connected_panels}
                  </LabeledList.Item>
                </LabeledList>
              </Table.Cell>
              <Table.Cell>
                <LabeledList>
                  <StatBar
                    label="Power output"
                    ranges={{
                      good: [0.66, Infinity],
                      average: [0.33, 0.66],
                      bad: [-Infinity, 0.33],
                    }}
                    minValue={0}
                    maxValue={1}
                    value={generated_ratio}
                  >
                    {`${generated} W`}
                  </StatBar>
                  <LabeledList.Item label="Star orientation">
                    {sun_angle}°
                  </LabeledList.Item>
                </LabeledList>
              </Table.Cell>
            </Table.Row>
          </Table>
        </Section>
        <Section title="Controls">
          <LabeledList>
            <LabeledList.Item label="Tracking">
              <Button
                icon="times"
                selected={tracking_state === 0}
                onClick={() => act('tracking', { mode: 0 })}
              >
                Off
              </Button>
              <Button
                icon="clock-o"
                selected={tracking_state === 1}
                onClick={() => act('tracking', { mode: 1 })}
              >
                Timed
              </Button>
              <Button
                icon="sync"
                selected={tracking_state === 2}
                disabled={!connected_tracker}
                onClick={() => act('tracking', { mode: 2 })}
              >
                Auto
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Azimuth">
              {(tracking_state === 0 || tracking_state === 1) && (
                <NumberInput
                  tickWhileDragging
                  width="52px"
                  unit="°"
                  step={1}
                  stepPixelSize={2}
                  minValue={-360}
                  maxValue={+720}
                  value={array_angle}
                  format={(rate) => {
                    const sign = Math.sign(rate) > 0 ? ' (CW)' : ' (CCW)';
                    return Math.abs(rate).toFixed() + sign;
                  }}
                  onChange={(value) => act('azimuth', { value })}
                />
              )}
              {tracking_state === 1 && (
                <NumberInput
                  tickWhileDragging
                  width="80px"
                  unit="deg/h"
                  step={1}
                  minValue={-max_rotation_rate - 0.01}
                  maxValue={max_rotation_rate + 0.01}
                  value={rotation_rate}
                  format={(rate) => {
                    const sign = Math.sign(rate) > 0 ? ' (CW)' : ' (CCW)';
                    return Math.abs(rate).toFixed() + sign;
                  }}
                  onChange={(value) => act('azimuth_rate', { value })}
                />
              )}
              {tracking_state === 2 && (
                <Label inline mt="3px">
                  {`${array_angle}°`} (auto)
                </Label>
              )}
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
