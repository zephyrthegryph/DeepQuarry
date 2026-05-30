// Prison shuttle dispatch console — TGUI.
//
// Single-button dispatch: depending on the shuttle's current location,
// either "Send to Station" or "Send to Dock". While in transit, the
// console shows time remaining instead.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Data = {
  moving: BooleanLike;
  at_station: BooleanLike;
  time_left: number;
  can_move: BooleanLike;
};

export const PrisonShuttleConsole = () => {
  const { data, act } = useBackend<Data>();
  const { moving, at_station, time_left, can_move } = data;

  const locationLabel = moving
    ? `In transit (${time_left}s)`
    : at_station
      ? 'Station'
      : 'Dock';

  return (
    <Window width={420} height={220}>
      <Window.Content>
        <Section title="Prison Shuttle">
          <LabeledList>
            <LabeledList.Item label="Location">
              <Box inline bold>
                {locationLabel}
              </Box>
            </LabeledList.Item>
          </LabeledList>
          <Box mt={2}>
            {moving ? (
              <Box color="average" italic>
                Shuttle already called.
              </Box>
            ) : at_station ? (
              <Button
                fluid
                icon="arrow-right"
                color="bad"
                disabled={!can_move}
                onClick={() => act('send_to_dock')}
              >
                Send to Dock
              </Button>
            ) : (
              <Button
                fluid
                icon="arrow-right"
                color="good"
                disabled={!can_move}
                onClick={() => act('send_to_station')}
              >
                Send to Station
              </Button>
            )}
          </Box>
        </Section>
      </Window.Content>
    </Window>
  );
};
