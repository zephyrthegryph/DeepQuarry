import { useBackend } from 'tgui/backend';
import { Button, Knob, LabeledList } from 'tgui-core/components';

import type { Data } from './types';

export const OperatingComputerOptions = (props) => {
  const { act, data } = useBackend<Data>();
  const { verbose, health, healthAlarm, spo2, spo2Alarm, crit } = data;
  return (
    <LabeledList>
      <LabeledList.Item label="Loudspeaker">
        <Button
          selected={verbose}
          icon={verbose ? 'toggle-on' : 'toggle-off'}
          onClick={() => act(verbose ? 'verboseOff' : 'verboseOn')}
        >
          {verbose ? 'On' : 'Off'}
        </Button>
      </LabeledList.Item>
      <LabeledList.Item label="Health Announcer">
        <Button
          selected={health}
          icon={health ? 'toggle-on' : 'toggle-off'}
          onClick={() => act(health ? 'healthOff' : 'healthOn')}
        >
          {health ? 'On' : 'Off'}
        </Button>
      </LabeledList.Item>
      <LabeledList.Item label="Health Announcer Threshold">
        <Knob
          bipolar
          minValue={-100}
          maxValue={100}
          value={healthAlarm}
          stepPixelSize={5}
          ml="0"
          format={(val) => `${val.toFixed()}%`}
          onChange={(e, val: number) =>
            act('health_adj', {
              new: val,
            })
          }
        />
      </LabeledList.Item>
      <LabeledList.Item label="SpO2 Alarm">
        <Button
          selected={spo2}
          icon={spo2 ? 'toggle-on' : 'toggle-off'}
          onClick={() => act(spo2 ? 'spo2Off' : 'spo2On')}
        >
          {spo2 ? 'On' : 'Off'}
        </Button>
      </LabeledList.Item>
      <LabeledList.Item label="SpO2 Alarm Threshold">
        <Knob
          minValue={0}
          maxValue={100}
          value={spo2Alarm}
          stepPixelSize={5}
          ml="0"
          format={(val) => `${val.toFixed()}%`}
          onChange={(e, val: number) =>
            act('spo2_adj', {
              new: val,
            })
          }
        />
      </LabeledList.Item>
      <LabeledList.Item label="Critical Alert">
        <Button
          selected={crit}
          icon={crit ? 'toggle-on' : 'toggle-off'}
          onClick={() => act(crit ? 'critOff' : 'critOn')}
        >
          {crit ? 'On' : 'Off'}
        </Button>
      </LabeledList.Item>
    </LabeledList>
  );
};
