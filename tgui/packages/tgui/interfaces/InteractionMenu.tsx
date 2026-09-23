import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, NoticeBox, Section, Stack } from 'tgui-core/components';

type Available = {
  id: string;
  name: string;
  category: string | null;
  keys: string[];
};

type Blocked = {
  id: string;
  name: string;
  category: string | null;
  reason: string;
};

type Action = {
  id: string;
  name: string;
};

type Data = {
  target: string | null;
  available: Available[];
  blocked: Blocked[];
  actions: Action[];
  verbs: string[];
};

/** The interaction menu: what you can do to a target, what you can't and why. */
export const InteractionMenu = (props) => {
  const { act, data } = useBackend<Data>();
  const {
    target,
    available = [],
    blocked = [],
    actions = [],
    verbs = [],
  } = data;

  return (
    <Window title={target || 'Interactions'} width={320} height={420}>
      <Window.Content scrollable>
        {!target ? (
          <NoticeBox>It's gone.</NoticeBox>
        ) : (
          <Stack vertical>
            <Stack.Item>
              <Section title="Interactions">
                {available.length === 0 && blocked.length === 0 && (
                  <Box color="label">Nothing to do here.</Box>
                )}
                {available.map((entry) => (
                  <Button
                    key={entry.id}
                    fluid
                    onClick={() => act('run', { id: entry.id })}
                  >
                    <Stack>
                      <Stack.Item grow>{entry.name}</Stack.Item>
                      {entry.keys.length > 0 && (
                        <Stack.Item color="label">
                          {entry.keys.join(', ')}
                        </Stack.Item>
                      )}
                    </Stack>
                  </Button>
                ))}
                {blocked.map((entry) => (
                  <Box key={entry.id} my={0.5} color="grey">
                    {entry.name}
                    <Box inline color="average" ml={1}>
                      {entry.reason}
                    </Box>
                  </Box>
                ))}
              </Section>
            </Stack.Item>
            <Stack.Item>
              <Section title="Actions">
                {actions.map((entry) => (
                  <Button
                    key={entry.id}
                    onClick={() => act('action', { id: entry.id })}
                  >
                    {entry.name}
                  </Button>
                ))}
              </Section>
            </Stack.Item>
            {verbs.length > 0 && (
              <Stack.Item>
                <Section title="Commands">
                  {verbs.map((name) => (
                    <Button
                      key={name}
                      fluid
                      onClick={() => act('verb', { name })}
                    >
                      {name}
                    </Button>
                  ))}
                </Section>
              </Stack.Item>
            )}
          </Stack>
        )}
      </Window.Content>
    </Window>
  );
};
