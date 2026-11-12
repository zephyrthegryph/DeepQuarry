import { useBackend } from 'tgui/backend';
import { Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import type { SleeperActions, SleeperData } from '../generated/Sleeper';
import { StatBar } from 'tgui/components/StatBar';
import { Label } from 'tgui/components/Label';

export const SleeperDialysisPump = (props: {
  active: BooleanLike;
  actToDo: string;
  title: string;
}) => {
  const { act, data } = useBackend<SleeperData, SleeperActions>();

  const { active, actToDo, title } = props;

  const { isBeakerLoaded, beakerMaxSpace, beakerFreeSpace } = data;

  const canDialysis = active && beakerFreeSpace > 0;
  return (
    <Section
      title={title}
      buttons={
        <Stack>
          <Stack.Item>
            <Button
              disabled={!isBeakerLoaded || beakerFreeSpace <= 0}
              selected={canDialysis}
              icon={canDialysis ? 'toggle-on' : 'toggle-off'}
              onClick={() => act(actToDo)}
            >
              {canDialysis ? 'Active' : 'Inactive'}
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button
              disabled={!isBeakerLoaded}
              icon="eject"
              onClick={() => act('removebeaker')}
            >
              Eject
            </Button>
          </Stack.Item>
        </Stack>
      }
    >
      {isBeakerLoaded ? (
        <LabeledList>
          <StatBar
            label="Remaining Space"
            minValue={0}
            maxValue={1}
            value={beakerFreeSpace / beakerMaxSpace}
            ranges={{
              good: [0.5, Infinity],
              average: [0.25, 0.5],
              bad: [-Infinity, 0.25],
            }}
          >
            {beakerFreeSpace}u
          </StatBar>
        </LabeledList>
      ) : (
        <Label>No beaker loaded.</Label>
      )}
    </Section>
  );
};
