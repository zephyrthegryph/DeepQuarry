// Orion Trail — structured TGUI.
//
// State-machine arcade game. The DM side picks one of four screens
// (start / normal / event / gameover) and React renders the matching
// component. The event screen is a title, story lines and a list of choices.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';

type EventAction = {
  action: string | null;
  label: string;
  arg?: string | null;
  value?: number | null;
};

type Screen = 'start' | 'normal' | 'event' | 'gameover';

type Data = {
  screen: Screen;
  // Game-over
  reasons?: string[];
  // Event
  event_title?: string;
  event_lines?: string[];
  event_actions?: EventAction[];
  // Normal stop
  turn?: number;
  stop_name?: string;
  stop_blurb?: string;
  crew?: string[];
  food?: number;
  fuel?: number;
  engine?: number;
  hull?: number;
  electronics?: number;
  at_blackhole?: boolean;
};

export const OrionTrail = () => {
  const { data, act } = useBackend<Data>();
  switch (data.screen) {
    case 'gameover':
      return (
        <Window width={520} height={400} title="The Orion Trail">
          <Window.Content>
            <Section title="Game Over">
              <Box mb={1}>
                Like many before you, your crew never made it to Orion, lost to
                space… <b>forever</b>.
              </Box>
              {(data.reasons ?? []).map((r, i) => (
                <Box key={i} color="bad" mb="2px">
                  {r}
                </Box>
              ))}
              <Box mt={2}>
                <Button onClick={() => act('menu')}>OK…</Button>
              </Box>
            </Section>
          </Window.Content>
        </Window>
      );
    case 'event':
      return (
        <Window width={520} height={420} title="The Orion Trail">
          <Window.Content scrollable>
            <Section title={data.event_title ?? ''}>
              {(data.event_lines ?? []).map((line, i) => (
                <Box key={i} mb={1}>
                  {line}
                </Box>
              ))}
              <Stack vertical align="flex-end">
                {(data.event_actions ?? []).map((choice, i) =>
                  choice.action ? (
                    <Stack.Item key={i}>
                      <Button
                        onClick={() =>
                          act(
                            choice.action as string,
                            choice.arg ? { [choice.arg]: choice.value } : undefined,
                          )
                        }
                      >
                        {choice.label}
                      </Button>
                    </Stack.Item>
                  ) : (
                    <Stack.Item key={i} color="label">
                      {choice.label}
                    </Stack.Item>
                  ),
                )}
                <Stack.Item>
                  <Button onClick={() => act('close')}>Close</Button>
                </Stack.Item>
              </Stack>
            </Section>
          </Window.Content>
        </Window>
      );
    case 'normal':
      return (
        <Window width={520} height={500} title="The Orion Trail">
          <Window.Content scrollable>
            <Section title={data.stop_name ?? ''}>
              <Box mb={1}>{data.stop_blurb}</Box>
            </Section>
            <Section title="Crew">
              <Box mb={1}>{(data.crew ?? []).join(', ') || 'None'}</Box>
              <LabeledList>
                <LabeledList.Item label="Food">{data.food}</LabeledList.Item>
                <LabeledList.Item label="Fuel">{data.fuel}</LabeledList.Item>
                <LabeledList.Item label="Engine Parts">
                  {data.engine}
                </LabeledList.Item>
                <LabeledList.Item label="Hull Panels">
                  {data.hull}
                </LabeledList.Item>
                <LabeledList.Item label="Electronics">
                  {data.electronics}
                </LabeledList.Item>
              </LabeledList>
            </Section>
            <Section>
              <Stack>
                {data.at_blackhole ? (
                  <>
                    <Stack.Item>
                      <Button
                        icon="rotate-left"
                        onClick={() => act('blackhole_around')}
                      >
                        Go Around
                      </Button>
                    </Stack.Item>
                    <Stack.Item>
                      <Button
                        color="bad"
                        icon="forward"
                        onClick={() => act('blackhole_continue')}
                      >
                        Continue
                      </Button>
                    </Stack.Item>
                  </>
                ) : (
                  <Stack.Item>
                    <Button icon="forward" onClick={() => act('continue')}>
                      Continue
                    </Button>
                  </Stack.Item>
                )}
                <Stack.Item>
                  <Button
                    color="bad"
                    icon="skull"
                    onClick={() => act('killcrew')}
                  >
                    Kill a crewmember
                  </Button>
                </Stack.Item>
                <Stack.Item>
                  <Button onClick={() => act('close')}>Close</Button>
                </Stack.Item>
              </Stack>
            </Section>
          </Window.Content>
        </Window>
      );
    default:
      return (
        <Window width={420} height={280} title="The Orion Trail">
          <Window.Content>
            <Section title="The Orion Trail">
              <Box mb={2}>Experience the journey of your ancestors!</Box>
              <Button
                color="good"
                icon="rocket"
                onClick={() => act('new_game')}
              >
                New Game
              </Button>{' '}
              <Button onClick={() => act('close')}>Close</Button>
            </Section>
          </Window.Content>
        </Window>
      );
  }
};
