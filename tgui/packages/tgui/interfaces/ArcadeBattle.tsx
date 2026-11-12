import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type {
  ArcadeBattleActions,
  ArcadeBattleData,
} from './generated/ArcadeBattle';
import { StatBar } from 'tgui/components/StatBar';

type Data = ArcadeBattleData;

export const ArcadeBattle = (props) => {
  const { act, data } = useBackend<Data, ArcadeBattleActions>();

  const {
    temp,
    enemyAction,
    enemyName,
    playerHP,
    playerMP,
    enemyHP,
    gameOver,
  } = data;

  return (
    <Window width={400} height={240}>
      <Window.Content>
        <Section title={enemyName} textAlign="center">
          <Section color="label">
            <Box>{temp}</Box>
            <Box>{!gameOver && enemyAction}</Box>
          </Section>
          <Stack>
            <Stack.Item>
              <LabeledList>
                <StatBar
                  label="Player Health"
                  value={playerHP}
                  minValue={0}
                  maxValue={30}
                  ranges={{
                    olive: [31, Infinity],
                    good: [20, 31],
                    average: [10, 20],
                    bad: [-Infinity, 10],
                  }}
                >
                  {playerHP}HP
                </StatBar>
                <StatBar
                  label="Player Magic"
                  value={playerMP}
                  minValue={0}
                  maxValue={10}
                  ranges={{
                    purple: [11, Infinity],
                    violet: [3, 11],
                    bad: [-Infinity, 3],
                  }}
                >
                  {playerMP}MP
                </StatBar>
              </LabeledList>
            </Stack.Item>
            <Stack.Item>
              <LabeledList>
                <StatBar
                  label="Enemy HP"
                  value={enemyHP}
                  minValue={0}
                  maxValue={45}
                  ranges={{
                    olive: [31, Infinity],
                    good: [20, 31],
                    average: [10, 20],
                    bad: [-Infinity, 10],
                  }}
                >
                  {enemyHP}HP
                </StatBar>
              </LabeledList>
            </Stack.Item>
          </Stack>
          {(gameOver && (
            <Button fluid mt={1} color="green" onClick={() => act('newgame')}>
              New Game
            </Button>
          )) || (
            <Stack mt={2} justify="space-between">
              <Stack.Item grow>
                <Button
                  fluid
                  icon="fist-raised"
                  tooltip="Go in for the kill!"
                  tooltipPosition="top"
                  onClick={() => act('attack')}
                >
                  Attack!
                </Button>
              </Stack.Item>
              <Stack.Item grow>
                <Button
                  fluid
                  icon="band-aid"
                  tooltip="Heal yourself!"
                  tooltipPosition="top"
                  onClick={() => act('heal')}
                >
                  Heal!
                </Button>
              </Stack.Item>
              <Stack.Item grow>
                <Button
                  fluid
                  icon="magic"
                  tooltip="Recharge your magic!"
                  tooltipPosition="top"
                  onClick={() => act('charge')}
                >
                  Recharge!
                </Button>
              </Stack.Item>
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
