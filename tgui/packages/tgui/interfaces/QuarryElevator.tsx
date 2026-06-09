// Elevator panel TGUI.
//
// Two modes, branched on data.panel_role:
//   "surface" — full dispatch panel at the surface bay. Lists every
//               unlocked depth with stability + danger + goals and a
//               Dispatch button per depth.
//   "call"    — exterior call panel in a mine. Shows just the one
//               depth the panel is on, with the same stability /
//               danger / goal display, plus a Call button.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  Collapsible,
  ProgressBar,
  Section,
  Stack,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type GoalEntry = {
  name: string;
  description: string;
  progress: number;
  target: number;
  percent: number;
  satisfied: BooleanLike;
};

type Depth = {
  depth: number;
  loaded: BooleanLike;
  snapshot: BooleanLike;
  stability?: number;
  stability_threshold?: number;
  danger: number;
  danger_label: string;
  goals?: GoalEntry[];
};

type Frontier = {
  depth: number;
  unreachable: BooleanLike;
} | null;

type Data = {
  traveling: BooleanLike;
  current_depth: number;
  unlocked_depth: number;
  deepest_visited: number;
  panel_role: 'surface' | 'call';
  panel_depth: number;
  depths: Depth[];
  frontier: Frontier;
};

export const QuarryElevator = () => {
  const { data, act } = useBackend<Data>();
  const {
    traveling,
    current_depth,
    depths,
    frontier,
    deepest_visited,
    panel_role,
    panel_depth,
  } = data;

  const isCallPanel = panel_role === 'call';
  const title = isCallPanel
    ? `Exterior Call - Depth ${panel_depth}`
    : 'Freight Elevator';
  const blurb = isCallPanel
    ? 'This panel summons the elevator car to this depth.'
    : 'Pick a destination. A layer is stabilised — and unlocks the next depth — when the average of its goal progress is high enough.';

  return (
    <Window width={580} height={620}>
      <Window.Content scrollable>
        <Section
          title={title}
          buttons={
            <Box color="label">
              Car at:{' '}
              <Box inline bold>
                {current_depth === 0 ? 'Surface' : `Depth ${current_depth}`}
              </Box>
              {traveling ? (
                <Box inline color="average" ml={1}>
                  (In transit)
                </Box>
              ) : null}
            </Box>
          }
        >
          <Box color="label" mb={1}>
            {blurb}
          </Box>

          <Stack vertical fill>
            {depths.map((d) => (
              <Stack.Item key={d.depth}>
                <DepthCard
                  depth={d}
                  isCallPanel={isCallPanel}
                  onAction={() =>
                    isCallPanel
                      ? act('call')
                      : act('dispatch', { depth: d.depth })
                  }
                  traveling={!!traveling}
                />
              </Stack.Item>
            ))}
            {frontier ? (
              <Stack.Item>
                <FrontierCard
                  frontier={frontier}
                  deepestVisited={deepest_visited}
                />
              </Stack.Item>
            ) : null}
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};

const dangerColor = (label: string) => {
  switch (label) {
    case 'Critical':
      return 'bad';
    case 'Dangerous':
      return 'average';
    case 'Restless':
      return 'average';
    default:
      return 'good';
  }
};

const DepthCard = (props: {
  depth: Depth;
  isCallPanel: boolean;
  onAction: () => void;
  traveling: boolean;
}) => {
  const d = props.depth;
  const hasGoals = (d.goals?.length ?? 0) > 0;
  const stability = d.stability ?? 0;
  const threshold = d.stability_threshold ?? 80;
  const stable = stability >= threshold;
  const satisfiedCount = d.goals?.filter((g) => !!g.satisfied).length ?? 0;
  const totalCount = d.goals?.length ?? 0;
  const danger = d.danger ?? 0;

  return (
    <Section
      title={`Depth ${d.depth}`}
      buttons={
        <Button
          color={props.isCallPanel ? 'good' : stable ? 'good' : 'average'}
          disabled={props.traveling}
          onClick={props.onAction}
        >
          {props.isCallPanel ? 'Call Elevator' : 'Dispatch'}
        </Button>
      }
    >
      {/* Danger bar always shown. */}
      <Box mb={1}>
        <Box mb="2px">
          <Box inline bold mr={1}>
            Danger
          </Box>
          <Box inline color={dangerColor(d.danger_label)}>
            {d.danger_label}
          </Box>
        </Box>
        <ProgressBar
          value={danger}
          minValue={0}
          maxValue={100}
          ranges={{
            bad: [85, Infinity],
            average: [30, 85],
            good: [-Infinity, 30],
          }}
        >
          {danger}%
        </ProgressBar>
      </Box>

      {hasGoals ? (
        <Box>
          <Box mb="2px">
            <Box inline bold mr={1}>
              {stable ? (
                <Box inline color="good" mr={1}>
                  ✓
                </Box>
              ) : null}
              Stability
            </Box>
            <Box inline color="label">
              {satisfiedCount} / {totalCount} goals complete · target{' '}
              {threshold}%
            </Box>
          </Box>
          <ProgressBar
            value={stability}
            minValue={0}
            maxValue={100}
            ranges={{
              good: [threshold, Infinity],
              average: [threshold / 2, threshold],
              bad: [-Infinity, threshold / 2],
            }}
          >
            {stability}%
          </ProgressBar>

          <Box mt={1}>
            <Collapsible
              title={`Goals (${satisfiedCount}/${totalCount} complete)`}
              color="transparent"
            >
              <Stack vertical fill>
                {d.goals!.map((g, i) => (
                  <Stack.Item key={i}>
                    <GoalRow goal={g} />
                  </Stack.Item>
                ))}
              </Stack>
            </Collapsible>
          </Box>
        </Box>
      ) : (
        <Box color="label">No goal data available for this depth.</Box>
      )}
    </Section>
  );
};

const GoalRow = (props: { goal: GoalEntry }) => {
  const g = props.goal;
  const satisfied = !!g.satisfied;
  return (
    <Box mb="2px">
      <Box mb="1px">
        {satisfied ? (
          <Box inline color="good" mr={1}>
            ✓
          </Box>
        ) : null}
        <Box inline bold>
          {g.name}
        </Box>
        <Box inline color="label" ml={1} fontSize="0.85em">
          {g.progress} / {g.target}
        </Box>
      </Box>
      {g.description ? (
        <Box color="label" fontSize="0.85em" mb="1px">
          {g.description}
        </Box>
      ) : null}
      <ProgressBar
        value={g.percent}
        minValue={0}
        maxValue={100}
        ranges={{
          good: [100, Infinity],
          average: [50, 100],
          bad: [-Infinity, 50],
        }}
      >
        {g.percent}%
      </ProgressBar>
    </Box>
  );
};

const FrontierCard = (props: {
  frontier: NonNullable<Frontier>;
  deepestVisited: number;
}) => {
  return (
    <Section title={`Depth ${props.frontier.depth}`}>
      <Box color="bad" bold>
        Locked
      </Box>
      <Box color="label" mt="4px" fontSize="0.9em">
        Stabilise depth {props.deepestVisited} (complete enough of its goals) to
        unlock the next descent.
      </Box>
    </Section>
  );
};
