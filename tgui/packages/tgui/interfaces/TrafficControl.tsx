// Telecommunications Traffic Control — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, NoticeBox, Section, Stack } from 'tgui-core/components';
import type {
  TrafficControlActions,
  TrafficControlData,
} from './generated/TrafficControl';

export const TrafficControl = () => {
  const { data, act } = useBackend<TrafficControlData, TrafficControlActions>();
  const { temp, network, screen, servers, selected_id, autoruncode } = data;
  return (
    <Window width={520} height={520} title="Telecommunications Traffic Control">
      <Window.Content scrollable>
        {temp ? (
          <NoticeBox danger={temp.color === 'bad'}>
            <Box inline verticalAlign="middle">
              {temp.text}
            </Box>
            <Button
              icon="times-circle"
              style={{ float: 'right' }}
              onClick={() => act('clear_temp')}
            />
            <Box style={{ clear: 'both' }} />
          </NoticeBox>
        ) : null}
        {screen === 0 ? (
          <Section title="Main Menu">
            <Box mb={1}>
              Current Network:{' '}
              <Button onClick={() => act('set_network')}>{network}</Button>
            </Box>
            {servers.length > 0 ? (
              <>
                <Box mb="2px" bold>
                  Detected Telecommunication Servers:
                </Box>
                <Stack vertical>
                  {servers.map((s) => (
                    <Stack.Item key={s.id}>
                      <Button
                        fluid
                        onClick={() => act('view_server', { id: s.id })}
                      >
                        {s.name} ({s.id})
                      </Button>
                    </Stack.Item>
                  ))}
                </Stack>
                <Box mt={1}>
                  <Button
                    color="bad"
                    icon="trash"
                    onClick={() => act('flush_buffer')}
                  >
                    Flush Buffer
                  </Button>
                </Box>
              </>
            ) : (
              <Box>
                No servers detected.{' '}
                <Button icon="search" onClick={() => act('scan')}>
                  Scan
                </Button>
              </Box>
            )}
          </Section>
        ) : (
          <Section
            title={`Server ${selected_id ?? ''}`}
            buttons={
              <>
                <Button onClick={() => act('main_menu')}>Main Menu</Button>{' '}
                <Button onClick={() => act('refresh')}>Refresh</Button>
              </>
            }
          >
            <Box mb={1}>Current Network: {network}</Box>
            <Box mb={1}>
              <Button icon="code" onClick={() => act('edit_code')}>
                Edit Code
              </Button>
            </Box>
            <Box>
              Signal Execution:{' '}
              <Button
                selected={!!autoruncode}
                onClick={() => act('toggle_run')}
              >
                {autoruncode ? 'ALWAYS' : 'NEVER'}
              </Button>
            </Box>
          </Section>
        )}
      </Window.Content>
    </Window>
  );
};
