// Special Operations Shuttle console — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type {
  SpecopsShuttleActions,
  SpecopsShuttleData,
} from './generated/SpecopsShuttle';
import { Label } from 'tgui/components/Label';

export const SpecopsShuttle = () => {
  const { data, act } = useBackend<SpecopsShuttleData, SpecopsShuttleActions>();
  const { status_message, state, timeleft, destination } = data;
  return (
    <Window width={460} height={300} title="Special Operations Shuttle">
      <Window.Content>
        <Section title="Special Operations Shuttle">
          {status_message ? (
            <Box italic>{status_message}</Box>
          ) : state === 'moving' ? (
            <>
              <LabeledList>
                <LabeledList.Item label="Location">
                  Departing for {destination} in {timeleft} seconds.
                </LabeledList.Item>
              </LabeledList>
              <Label mt={1} italic>
                The Special Ops. shuttle is already leaving.
              </Label>
            </>
          ) : state === 'at_station' ? (
            <>
              <LabeledList>
                <LabeledList.Item label="Location">Station</LabeledList.Item>
              </LabeledList>
              <Box mt={1}>
                <Button icon="rocket" onClick={() => act('send_to_dock')}>
                  Shuttle standing by — recall to dock
                </Button>
              </Box>
            </>
          ) : (
            <>
              <LabeledList>
                <LabeledList.Item label="Location">Dock</LabeledList.Item>
              </LabeledList>
              <Box mt={1}>
                <Button icon="rocket" onClick={() => act('send_to_station')}>
                  Depart to {destination}
                </Button>
              </Box>
            </>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
