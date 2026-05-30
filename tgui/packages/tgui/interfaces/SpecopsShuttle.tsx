// Special Operations Shuttle console — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';

type Data = {
  status_message?: string;
  state?: 'moving' | 'at_station' | 'at_dock';
  timeleft?: number;
  destination?: string;
};

export const SpecopsShuttle = () => {
  const { data, act } = useBackend<Data>();
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
              <Box mt={1} italic color="label">
                The Special Ops. shuttle is already leaving.
              </Box>
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
