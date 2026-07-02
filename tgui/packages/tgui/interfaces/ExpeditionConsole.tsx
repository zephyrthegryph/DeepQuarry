import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  Icon,
  LabeledList,
  Section,
  Stack,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type ObjectiveRow = {
  text: string;
  progress: string;
  state: number; // 1 incomplete, 2 complete, 3 failed
  required: BooleanLike;
};

type Offer = {
  index: number;
  name: string;
  desc: string;
  threat: string;
  brief: string;
  difficulty: string;
  objective: string;
  reward_points: number;
  reward_cash: number;
};

type Active = {
  name: string;
  status: string;
  difficulty: string;
  biome: string;
  threat: string;
  brief: string;
  size: string;
  z: number;
  objective: string;
  progress: string;
  objectives: ObjectiveRow[];
  failed: BooleanLike;
  complete: boolean;
};

const objectiveColor = (state: number) =>
  state === 2 ? 'good' : state === 3 ? 'bad' : 'label';

const objectiveIcon = (state: number) =>
  state === 2 ? 'circle-check' : state === 3 ? 'circle-xmark' : 'circle';

type Data = {
  cooldown: number;
  offers: Offer[];
  active: Active | null;
};

const difficultyColor = (d: string) => {
  switch (d) {
    case 'Low':
      return 'good';
    case 'Medium':
      return 'average';
    case 'High':
      return 'bad';
    default:
      return 'grey';
  }
};

export const ExpeditionConsole = () => {
  const { act, data } = useBackend<Data>();
  const { cooldown, offers = [], active } = data;
  const launchLocked = cooldown > 0 || !!active;

  return (
    <Window width={560} height={520} title="Expedition Control">
      <Window.Content scrollable>
        <Stack vertical fill>
          <Stack.Item>
            <Section title="Active Expedition">
              {active ? (
                <>
                  <LabeledList>
                    <LabeledList.Item label="Designation">
                      {active.name} (z{active.z})
                    </LabeledList.Item>
                    <LabeledList.Item label="Status">
                      <Box color={active.complete ? 'good' : 'average'}>
                        {active.status}
                      </Box>
                    </LabeledList.Item>
                    <LabeledList.Item label="Difficulty">
                      <Box color={difficultyColor(active.difficulty)}>
                        {active.difficulty}
                      </Box>
                    </LabeledList.Item>
                    <LabeledList.Item label="Terrain">
                      {active.biome} · {active.size}
                    </LabeledList.Item>
                    <LabeledList.Item label="Threat">
                      {active.threat}
                    </LabeledList.Item>
                  </LabeledList>
                  <Box color="bad" mt={1}>
                    {active.brief}
                  </Box>
                  {active.failed ? (
                    <Box bold color="bad" mt={1}>
                      MISSION FAILED
                    </Box>
                  ) : null}
                  <Box bold mt={1} mb={0.5}>
                    Objectives
                  </Box>
                  {active.objectives.map((obj, i) => (
                    <Box key={i} color={objectiveColor(obj.state)}>
                      <Icon name={objectiveIcon(obj.state)} />{' '}
                      {obj.text}
                      {!obj.required ? ' (bonus)' : ''} — {obj.progress}
                    </Box>
                  ))}
                  <Box mt={1}>
                    <Button
                      icon="rocket"
                      color="good"
                      onClick={() => act('deploy')}
                    >
                      Deploy Pad Crew
                    </Button>
                    <Button
                      icon="arrow-rotate-left"
                      color="bad"
                      onClick={() => act('recall')}
                    >
                      Emergency Recall
                    </Button>
                  </Box>
                </>
              ) : (
                <Box color="label">
                  No expedition plotted. Select a mission from the board below.
                </Box>
              )}
            </Section>
          </Stack.Item>
          <Stack.Item grow>
            <Section
              title="Mission Board"
              buttons={
                <Button
                  icon="dice"
                  disabled={cooldown > 0}
                  tooltip={
                    cooldown > 0 ? `Locked (${cooldown}s)` : 'Reroll offers'
                  }
                  onClick={() => act('reroll')}
                >
                  Reroll
                </Button>
              }
            >
              {offers.length === 0 ? (
                <Box color="label">No mission offers available.</Box>
              ) : (
                offers.map((offer) => (
                  <Section
                    key={offer.index}
                    title={offer.name}
                    buttons={
                      <Button
                        icon="play"
                        color="good"
                        disabled={launchLocked}
                        tooltip={
                          active
                            ? 'An expedition is already underway'
                            : cooldown > 0
                              ? `Recharging (${cooldown}s)`
                              : undefined
                        }
                        onClick={() => act('launch', { index: offer.index })}
                      >
                        Launch
                      </Button>
                    }
                  >
                    <Box italic mb={1}>
                      {offer.desc}
                    </Box>
                    <Box color="bad" mb={1}>
                      {offer.brief}
                    </Box>
                    <LabeledList>
                      <LabeledList.Item label="Difficulty">
                        <Box color={difficultyColor(offer.difficulty)}>
                          {offer.difficulty}
                        </Box>
                      </LabeledList.Item>
                      <LabeledList.Item label="Threat">
                        {offer.threat}
                      </LabeledList.Item>
                      <LabeledList.Item label="Objective">
                        {offer.objective}
                      </LabeledList.Item>
                      <LabeledList.Item label="Reward">
                        {offer.reward_points} survey pts + {offer.reward_cash}{' '}
                        Thalers
                      </LabeledList.Item>
                    </LabeledList>
                  </Section>
                ))
              )}
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
