import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  ProgressBar,
  Section,
  Stack,
} from 'tgui-core/components';
import type {
  DNAForensicsActions,
  DNAForensicsData,
} from './generated/DNAForensics';

export const DNAForensics = (props) => {
  const { act, data } = useBackend<DNAForensicsData, DNAForensicsActions>();
  const { scan_progress, scanning, bloodsamp, bloodsamp_desc } = data;
  return (
    <Window width={540} height={326}>
      <Window.Content>
        <Section
          title="Status"
          buttons={
            <Stack>
              <Stack.Item>
                <Button
                  selected={scanning}
                  disabled={!bloodsamp}
                  icon="power-off"
                  onClick={() => act('scanItem')}
                >
                  {scanning ? 'Halt Scan' : 'Begin Scan'}
                </Button>
              </Stack.Item>
              <Stack.Item>
                <Button
                  disabled={!bloodsamp}
                  icon="eject"
                  onClick={() => act('ejectItem')}
                >
                  Eject Bloodsample
                </Button>
              </Stack.Item>
            </Stack>
          }
        >
          <LabeledList>
            <LabeledList.Item label="Scan Progress">
              <ProgressBar
                ranges={{
                  good: [99, Infinity],
                  violet: [-Infinity, 99],
                }}
                value={scan_progress}
                maxValue={100}
              />
            </LabeledList.Item>
          </LabeledList>
        </Section>
        <Section title="Blood Sample">
          {(bloodsamp && (
            <Box>
              {bloodsamp}
              <Box color="label">{bloodsamp_desc}</Box>
            </Box>
          )) || <Box color="bad">No blood sample inserted.</Box>}
        </Section>
      </Window.Content>
    </Window>
  );
};
