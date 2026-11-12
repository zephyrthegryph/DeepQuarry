// Syndicate (Virgo) beacon — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import type {
  SyndicateBeaconActions,
  SyndicateBeaconData,
} from './generated/SyndicateBeacon';
import { Label } from 'tgui/components/Label';

export const SyndicateBeacon = () => {
  const { data, act } = useBackend<
    SyndicateBeaconData,
    SyndicateBeaconActions
  >();
  const {
    temp,
    selfdestructing,
    recognized,
    connection_severed,
    user_ref,
    user_name,
    honorific,
  } = data;
  return (
    <Window width={520} height={360} title="Ominous Beacon">
      <Window.Content scrollable>
        <Section title="Ominous Beacon">
          <Box italic color="good">
            Scanning… Identity confirmed.
          </Box>
          {recognized ? (
            <Box italic color="good" mt={1}>
              Operative record found. Greetings, Agent {user_name}.
            </Box>
          ) : connection_severed ? (
            <Box italic color="bad" mt={1}>
              Connection severed.
            </Box>
          ) : (
            <>
              <Box italic color="bad" mt={1} mb={1}>
                Identity not found in operative database. What can the Black
                Market do for you today, {honorific} {user_name}?
              </Box>
              {!selfdestructing ? (
                <Button
                  onClick={() =>
                    act('transfer_supplies', { mob_ref: user_ref })
                  }
                >
                  "Send me some supplies!"
                </Button>
              ) : null}
            </>
          )}
          {temp ? (
            <Label italic mt={2}>
              {temp}
            </Label>
          ) : null}
        </Section>
      </Window.Content>
    </Window>
  );
};
