import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  FitText,
  LabeledList,
  NoticeBox,
  Section,
  Stack,
} from 'tgui-core/components';
import { toTitleCase } from 'tgui-core/string';

import { DIAGNOSIS_BAND } from '../common/Diagnosis';
import type { Data } from './types';

export const ComponentView = (props) => {
  const { act, data } = useBackend<Data>();

  const { diag_functional, components, faults } = data;

  if (components.length) {
    components.sort((a, b) => a.name.localeCompare(b.name));

    return (
      <Stack wrap align="flex-start" justify="space-between">
        {!!diag_functional && !!faults.length && (
          <Stack.Item basis="100%" ml={1}>
            <Section title="Faults">
              {faults.map((fault) => (
                <Box
                  key={`${fault.name}-${fault.location}`}
                  color={DIAGNOSIS_BAND[fault.band]?.color ?? 'label'}
                >
                  {fault.location
                    ? `${toTitleCase(fault.name)} (${fault.location})`
                    : toTitleCase(fault.name)}
                </Box>
              ))}
            </Section>
          </Stack.Item>
        )}
        {components.map((mod) => (
          <Stack.Item key={mod.key} basis="24%" grow ml={1}>
            <Section
              title={
                <FitText maxWidth={140} maxFontSize={18}>
                  {toTitleCase(mod.name)}
                </FitText>
              }
              height={12}
              mt={1}
              buttons={
                <Button
                  icon="power-off"
                  disabled={mod.name === 'power cell'}
                  selected={mod.toggled}
                  onClick={() =>
                    act('toggle_component', { component: mod.key })
                  }
                />
              }
            >
              {!!diag_functional && (
                <LabeledList>
                  <LabeledList.Item label="Damage">
                    <Box
                      bold
                      color={
                        mod.band ? DIAGNOSIS_BAND[mod.band].color : 'label'
                      }
                    >
                      {mod.band ? DIAGNOSIS_BAND[mod.band].label : 'Unknown'}
                    </Box>
                  </LabeledList.Item>
                </LabeledList>
              )}
              {diag_functional ? (
                <LabeledList>
                  <LabeledList.Item label="Powered">
                    {mod.is_powered || !mod.idle_usage ? (
                      <Box color="good">Yes</Box>
                    ) : (
                      <Box color="bad">No</Box>
                    )}
                  </LabeledList.Item>
                </LabeledList>
              ) : (
                <NoticeBox danger>DIAGNOSIS UNAVAILABLE</NoticeBox>
              )}
            </Section>
          </Stack.Item>
        ))}
      </Stack>
    );
  }

  return <NoticeBox danger>Diagnosis Module Offline</NoticeBox>;
};
