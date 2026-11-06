// Ignore List: the players whose OOC and deadchat messages do not appear to you.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, NoticeBox, Section, Stack } from 'tgui-core/components';

type Data = {
  ignored: string[];
};

export const IgnoreList = () => {
  const { data, act } = useBackend<Data>();
  const { ignored } = data;
  return (
    <Window width={380} height={420} title="Ignore List">
      <Window.Content scrollable>
        <Section
          title="Ignored players"
          buttons={
            <Button icon="plus" onClick={() => act('ignore')}>
              Ignore a player
            </Button>
          }
        >
          {ignored.length === 0 ? (
            <NoticeBox info>You are not ignoring any players.</NoticeBox>
          ) : (
            <Stack vertical>
              {ignored.map((key) => (
                <Stack.Item key={key}>
                  <Stack align="center">
                    <Stack.Item grow>{key}</Stack.Item>
                    <Stack.Item>
                      <Button
                        icon="xmark"
                        color="bad"
                        onClick={() => act('unignore', { key })}
                      >
                        Unignore
                      </Button>
                    </Stack.Item>
                  </Stack>
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
