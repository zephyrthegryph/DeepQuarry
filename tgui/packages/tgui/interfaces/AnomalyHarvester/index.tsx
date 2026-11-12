import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { LabeledList, Stack } from 'tgui-core/components';
import { capitalize } from 'tgui-core/string';
import type {
  AnomalyHarvesterActions,
  AnomalyHarvesterData,
} from '../generated/AnomalyHarvester';
import { SampleDisplay } from './Sample';
import { StatBar } from 'tgui/components/StatBar';

export const AnomalyHarvester = (props) => {
  const { act, data } = useBackend<
    AnomalyHarvesterData,
    AnomalyHarvesterActions
  >();
  const { points, pointsToGenerate, name } = data;

  const progress = (points / pointsToGenerate) * 100;
  return (
    <Window width={400} height={500}>
      <Window.Content>
        <Stack fill vertical>
          <Stack.Item>
            <LabeledList>
              <StatBar
                label="Sample Generation"
                value={progress}
                minValue={0}
                maxValue={100}
                ranges={{
                  good: [85, 100],
                  average: [25, 85],
                  bad: [0, 25],
                }}
              >
                <Stack align="baseline">
                  {!!name && <Stack.Item>{capitalize(name)}</Stack.Item>}
                  <Stack.Item grow>{`${progress.toFixed()}%`}</Stack.Item>
                </Stack>
              </StatBar>
            </LabeledList>
          </Stack.Item>
          <Stack.Item grow>
            <SampleDisplay />
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
