import { useBackend } from 'tgui/backend';
import { Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { SleeperActions, SleeperData } from '../generated/Sleeper';
import { stats, tempColors } from './constants';
import { StatBar } from 'tgui/components/StatBar';
import { Label } from 'tgui/components/Label';

export const SleeperOccupant = (props) => {
  const { act, data } = useBackend<SleeperData, SleeperActions>();
  const { occupant, auto_eject_dead, stasis } = data;
  if (!occupant) {
    return null;
  }
  return (
    <Section
      title="Occupant"
      buttons={
        <Stack>
          <Stack.Item>
            <Label inline>Auto-eject if dead:&nbsp;</Label>
          </Stack.Item>
          <Stack.Item>
            <Button
              icon={auto_eject_dead ? 'toggle-on' : 'toggle-off'}
              selected={auto_eject_dead}
              onClick={() =>
                act(`auto_eject_dead_${auto_eject_dead ? 'off' : 'on'}`)
              }
            >
              {auto_eject_dead ? 'On' : 'Off'}
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button icon="user-slash" onClick={() => act('ejectify')}>
              Eject
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button onClick={() => act('changestasis')}>{stasis}</Button>
          </Stack.Item>
        </Stack>
      }
    >
      <LabeledList>
        <LabeledList.Item label="Name">{occupant.name}</LabeledList.Item>
        <StatBar
          label="Health"
          minValue={0}
          maxValue={1}
          value={occupant.vitality / 100}
          color={
            occupant.critical
              ? 'bad'
              : occupant.vitality >= 50
                ? 'good'
                : 'average'
          }
        >
          {occupant.vitality.toFixed()}%
        </StatBar>
        <LabeledList.Item label="Status" color={stats[occupant.stat][0]}>
          {stats[occupant.stat][1]}
        </LabeledList.Item>
        <StatBar
          label="Temperature"
          minValue={0}
          maxValue={1}
          value={occupant.bodyTemperature / occupant.maxTemp}
          color={tempColors[occupant.temperatureSuitability + 3]}
        >
          {occupant.btCelsius.toFixed()}&deg;C,
          {occupant.btFaren.toFixed()}&deg;F
        </StatBar>
        {!!occupant.hasBlood && (
          <>
            <StatBar
              label="Blood Level"
              minValue={0}
              maxValue={1}
              value={occupant.bloodLevel! / occupant.bloodMax!}
              ranges={{
                bad: [-Infinity, 0.6],
                average: [0.6, 0.9],
                good: [0.6, Infinity],
              }}
            >
              {occupant.bloodPercent}%, {occupant.bloodLevel}cl
            </StatBar>
            <LabeledList.Item label="Pulse" verticalAlign="middle">
              {occupant.pulse} BPM
            </LabeledList.Item>
          </>
        )}
      </LabeledList>
    </Section>
  );
};
