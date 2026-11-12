import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Button,
  Collapsible,
  NoticeBox,
  Section,
  Table,
} from 'tgui-core/components';
import type {
  ServerControlActions,
  ServerControlData,
} from './generated/ServerControl';

type Data = ServerControlData;

export const ServerControl = (props) => {
  const { act, data } = useBackend<Data, ServerControlActions>();
  const { server_connected, servers, consoles, logs } = data;
  if (!server_connected) {
    return (
      <Window width={575} height={450}>
        <Window.Content>
          <NoticeBox textAlign="center" danger>
            Not connected to a Server. Please sync one using a multitool.
          </NoticeBox>
        </Window.Content>
      </Window>
    );
  }
  return (
    <Window width={575} height={400}>
      <Window.Content scrollable>
        {!servers.length ? (
          <NoticeBox mt={2} info>
            No servers found.
          </NoticeBox>
        ) : (
          <Section>
            <Table textAlign="center">
              <Table.Row header>
                <Table.Cell>Research Servers</Table.Cell>
              </Table.Row>
              {servers.map((server) => (
                <Table.Row key={server.server_ref} className="candystripe">
                  <Table.Cell>
                    {server.server_name}
                    <Button
                      mt={1}
                      tooltip={server.server_details}
                      color={server.server_disabled ? 'bad' : 'good'}
                      content={server.server_disabled ? 'Offline' : 'Online'}
                      fluid
                      textAlign="center"
                      onClick={() =>
                        act('lockdown_server', {
                          selected_server: server.server_ref,
                        })
                      }
                    />
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          </Section>
        )}

        {!consoles.length ? (
          <NoticeBox mt={2} info>
            No consoles found.
          </NoticeBox>
        ) : (
          <Section align="right">
            <Table textAlign="center">
              <Table.Row header>
                <Table.Cell>Research Consoles</Table.Cell>
              </Table.Row>
              {consoles.map((console) => (
                <Table.Row key={console.console_ref} className="candystripe">
                  <Table.Cell>
                    {console.console_name} - Location:{' '}
                    {console.console_location}
                    <Button
                      mt={1}
                      color={console.console_locked ? 'bad' : 'good'}
                      content={console.console_locked ? 'LOCKED' : 'UNLOCKED'}
                      fluid
                      textAlign="center"
                      onClick={() =>
                        act('lock_console', {
                          selected_console: console.console_ref,
                        })
                      }
                    />
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          </Section>
        )}

        <Collapsible title="Research History">
          {!logs.length ? (
            <NoticeBox mt={2} info>
              No history found.
            </NoticeBox>
          ) : (
            <Section>
              <Table>
                <Table.Row header>
                  <Table.Cell>Research Name</Table.Cell>
                  <Table.Cell>Cost</Table.Cell>
                  <Table.Cell>Researcher Name</Table.Cell>
                  <Table.Cell>Console Location</Table.Cell>
                </Table.Row>
                {logs.map((server_log) => (
                  <Table.Row
                    mt={1}
                    key={server_log.node_name}
                    className="candystripe"
                  >
                    <Table.Cell>{server_log.node_name}</Table.Cell>
                    <Table.Cell>{server_log.node_cost}</Table.Cell>
                    <Table.Cell>{server_log.node_researcher}</Table.Cell>
                    <Table.Cell>{server_log.node_research_location}</Table.Cell>
                  </Table.Row>
                ))}
              </Table>
            </Section>
          )}
        </Collapsible>
      </Window.Content>
    </Window>
  );
};
