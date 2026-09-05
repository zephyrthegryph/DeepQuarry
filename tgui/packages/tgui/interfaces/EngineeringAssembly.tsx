import {
  Box,
  LabeledList,
  NoticeBox,
  NumberInput,
  ProgressBar,
  Section,
  Stack,
} from 'tgui-core/components';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Data = {
  status: string;
  temperature: number;
  buffer: number;
  input: number;
  output: number;
  lossEnergy: number;
  limiting?: string;
  configuration: number;
  liner: number;
  shell: number;
  fatigue: number;
  monitoring: boolean;
  parts: {
    role: string;
    material: string;
    meltingPoint: number;
    corrosion: number;
    purpose: string;
  }[];
  reading?: Record<string, string | number>;
  emitter?: {
    output: number;
    cadence: number;
    stored: number;
    active: boolean;
  };
};
const number = (value: number) => Math.round(value).toLocaleString();
const measurementFields = [
  ['name', 'Assembly', ''],
  ['assembly', 'Serial', ''],
  ['duration', 'Observed duration', 's'],
  ['minimum_output_watts', 'Minimum delivered power', 'W'],
  ['minimum_flow_moles', 'Minimum gas transfer', 'mol/s'],
  ['minimum_pressure_kpa', 'Minimum delivery pressure', 'kPa'],
  ['maximum_temperature_k', 'Peak temperature', 'K'],
  ['efficiency', 'Measured efficiency', '%'],
] as const;

export const EngineeringAssembly = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Window width={620} height={620}>
      <Window.Content scrollable>
        <Section title={data.status}>
          <LabeledList>
            <LabeledList.Item label="Temperature">
              {number(data.temperature)} K
            </LabeledList.Item>
            <LabeledList.Item label="Phase buffer">
              {number(data.buffer)} J stored
            </LabeledList.Item>
            <LabeledList.Item label="Measured power">
              {number(data.input)} W in / {number(data.output)} W delivered
            </LabeledList.Item>
            <LabeledList.Item label="Waste heat">
              {number(data.lossEnergy)} J total
            </LabeledList.Item>
            {data.limiting && (
              <LabeledList.Item label="Limit" color="orange">
                {data.limiting}
              </LabeledList.Item>
            )}
          </LabeledList>
          <Stack mt={1}>
            {(
              [
                ['Liner', data.liner],
                ['Shell', data.shell],
                ['Fatigue reserve', 100 - data.fatigue],
              ] as const
            ).map(([label, value]) => (
              <Stack.Item grow key={label}>
                <Box mb={0.5}>{label}</Box>
                <ProgressBar value={value / 100}>{number(value)}%</ProgressBar>
              </Stack.Item>
            ))}
          </Stack>
        </Section>
        {data.emitter && (
          <Section title="Emitter settings">
            <LabeledList>
              {(['output', 'cadence'] as const).map((setting) => (
                <LabeledList.Item
                  key={setting}
                  label={
                    setting === 'output' ? 'Pulse energy' : 'Pulse cadence'
                  }
                >
                  <NumberInput
                    value={data.emitter?.[setting] ?? 1}
                    minValue={0.25}
                    maxValue={3}
                    step={0.25}
                    unit="×"
                    onChange={(value) =>
                      act('emitter_setting', { setting, value })
                    }
                  />
                </LabeledList.Item>
              ))}
              <LabeledList.Item label="Reservoir">
                {number(data.emitter.stored)} J
              </LabeledList.Item>
            </LabeledList>
            <Box color="label" mt={1}>
              Output is limited by supplied power, installed parts, and
              temperature. Pulses wait until sufficient energy is stored.
            </Box>
          </Section>
        )}
        <Section title="Installed parts">
          <LabeledList>
            {data.parts.map((part) => (
              <LabeledList.Item key={part.role} label={part.role}>
                {part.material}
                <Box inline ml={1} color="label">
                  {number(part.meltingPoint)} K melt · {number(part.corrosion)}{' '}
                  corrosion resistance
                </Box>
                <Box color="label" mt={0.5}>
                  {part.purpose}
                </Box>
              </LabeledList.Item>
            ))}
          </LabeledList>
        </Section>
        <Section title="Measurement record">
          <NoticeBox info>
            {data.monitoring
              ? 'Keep the multitool in hand and remain beside the assembly. Its memory records continuous operation; print the reading at a photocopier.'
              : 'Right-click the assembly with a multitool to begin a new observation.'}
          </NoticeBox>
          {data.reading && (
            <LabeledList>
              {measurementFields.map(([key, label, unit]) => {
                const value = data.reading?.[key];
                if (
                  value === undefined ||
                  (key.startsWith('minimum_') && value === 0)
                ) {
                  return null;
                }
                return (
                  <LabeledList.Item key={key} label={label}>
                    {typeof value === 'number'
                      ? (key === 'efficiency'
                          ? value * 100
                          : value
                        ).toLocaleString(undefined, {
                          maximumFractionDigits: 1,
                        })
                      : value}
                    {unit && ` ${unit}`}
                  </LabeledList.Item>
                );
              })}
            </LabeledList>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
