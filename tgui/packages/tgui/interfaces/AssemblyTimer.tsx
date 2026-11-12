import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Button,
  LabeledList,
  NumberInput,
  Section,
} from 'tgui-core/components';
import { formatTime } from 'tgui-core/format';
import { round } from 'tgui-core/math';
import type {
  AssemblyTimerActions,
  AssemblyTimerData,
} from './generated/AssemblyTimer';

export const AssemblyTimer = (props) => {
  const { act, data } = useBackend<AssemblyTimerData, AssemblyTimerActions>();
  const { timing, time = 0 } = data;
  return (
    <Window width={400} height={110}>
      <Window.Content>
        <Section title="Timing Unit">
          <LabeledList>
            <LabeledList.Item
              label="Timer"
              buttons={
                <Button
                  icon="stopwatch"
                  selected={timing}
                  onClick={() => act('timing')}
                >
                  {timing ? 'Counting Down' : 'Disabled'}
                </Button>
              }
            >
              <NumberInput
                animated
                tickWhileDragging
                fluid
                step={1}
                value={time}
                minValue={0}
                maxValue={600}
                format={(val: number) => formatTime(round(val * 10, 0))}
                onChange={(val: number) => act('set_time', { time: val })}
              />
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
