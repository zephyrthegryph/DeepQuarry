// Keycard authentication device — TGUI.
//
// Two-screen flow: pick an event, then swipe two cards (one here, one
// at another device) to authorize.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';

type Data = {
  screen: number;
  event: string;
  ert_admin_only: number;
};

const EVENT_LABELS = [
  'Red alert',
  'Emergency Response Team',
  'Grant Emergency Maintenance Access',
  'Revoke Emergency Maintenance Access',
];

export const KeycardAuth = () => {
  const { data, act } = useBackend<Data>();
  const { screen, event, ert_admin_only } = data;

  const events = EVENT_LABELS.filter(
    (e) => e !== 'Emergency Response Team' || !ert_admin_only,
  );

  return (
    <Window width={500} height={280}>
      <Window.Content>
        <Section title="Keycard Authentication Device">
          <Box mb={1} color="label">
            This device triggers high-security events. It requires two
            high-level ID cards swiped simultaneously at different devices.
          </Box>
          {screen === 1 ? (
            <Stack vertical>
              {events.map((e) => (
                <Stack.Item key={e}>
                  <Button
                    fluid
                    onClick={() => act('triggerevent', { event: e })}
                  >
                    {e}
                  </Button>
                </Stack.Item>
              ))}
            </Stack>
          ) : (
            <>
              <Box mb={1}>
                Please swipe your card to authorize event:{' '}
                <Box inline bold>
                  {event}
                </Box>
              </Box>
              <Button icon="arrow-left" onClick={() => act('reset')}>
                Back
              </Button>
            </>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
