import { useBackend } from 'tgui/backend';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { ShuttleControlActions } from '../generated/ShuttleControl';
import { getDockingStatus } from './functions';
import type { Data } from './types';
import { Label } from 'tgui/components/Label';

export const ShuttleControlSharedShuttleStatus = (props: {
  engineName?: string;
}) => {
  const { act, data } = useBackend<Data, ShuttleControlActions>();
  const { engineName = 'Bluespace Drive' } = props;
  const {
    shuttle_status,
    shuttle_state,
    has_docking,
    docking_status,
    docking_override,
    docking_codes,
  } = data;
  return (
    <Section title="Shuttle Status">
      <Label mb={1}>{shuttle_status}</Label>
      <LabeledList>
        <LabeledList.Item label={engineName}>
          {(shuttle_state === 'idle' && (
            <Box color="#676767" bold>
              IDLE
            </Box>
          )) ||
            (shuttle_state === 'warmup' && (
              <Box color="#336699">SPINNING UP</Box>
            )) ||
            (shuttle_state === 'in_transit' && (
              <Box color="#336699">ENGAGED</Box>
            )) || <Box color="bad">ERROR</Box>}
        </LabeledList.Item>
        {(has_docking && (
          <>
            <LabeledList.Item label="Docking Status">
              {getDockingStatus(docking_status, docking_override)}
            </LabeledList.Item>
            <LabeledList.Item label="Docking Codes">
              <Button icon="pen" onClick={() => act('set_codes')}>
                {docking_codes || 'Not Set'}
              </Button>
            </LabeledList.Item>
          </>
        )) ||
          ''}
      </LabeledList>
    </Section>
  );
};
