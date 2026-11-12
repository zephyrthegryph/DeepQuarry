// The command panel: the commands of a mob (an AI's cameras and station
// commands, a cyborg's subsystems, a malfunctioning AI's hacks) in groups, in
// one console window. The server lists the groups, so a new command is a row
// in the DM list and no change here.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, NoticeBox, Section, Stack } from 'tgui-core/components';
import type {
  CommandPanelActions,
  CommandPanelData,
} from './generated/CommandPanel';

type Data = CommandPanelData;

export const CommandPanel = () => {
  const { data, act } = useBackend<Data, CommandPanelActions>();
  const { title, blocked, groups = [] } = data;
  return (
    <Window width={540} height={600} title={title} theme="console">
      <Window.Content scrollable>
        <Stack vertical>
          {!!blocked && (
            <Stack.Item>
              <NoticeBox danger>{blocked}</NoticeBox>
            </Stack.Item>
          )}
          {!groups.length && (
            <Stack.Item>
              <NoticeBox>There is nothing here for you.</NoticeBox>
            </Stack.Item>
          )}
          {groups.map((group) => (
            <Stack.Item key={group.title}>
              <Section title={group.title}>
                <Stack wrap>
                  {group.commands.map((command) => (
                    <Stack.Item key={command.id} basis="48%" grow>
                      <Button
                        fluid
                        disabled={!!blocked}
                        tooltip={command.desc}
                        onClick={() => act('run_command', { id: command.id })}
                      >
                        {command.label}
                      </Button>
                    </Stack.Item>
                  ))}
                </Stack>
              </Section>
            </Stack.Item>
          ))}
        </Stack>
      </Window.Content>
    </Window>
  );
};
