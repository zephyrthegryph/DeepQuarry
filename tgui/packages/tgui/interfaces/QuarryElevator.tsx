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
  rolling?: BooleanLike;
  archetype?: string;
  archetype_desc?: string;
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
  panel_role: 'surface' | 'call' | 'layer';
  panel_depth: number;
  depths: Depth[];
  frontier: Frontier;
  frontier_candidate_depth: number;
  frontier_locked: BooleanLike;
  frontier_roll_in: number;
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
    frontier_locked,
    frontier_roll_in,
  } = data;

  const isCallPanel = panel_role === 'call';
  const isLayer = panel_role === 'layer';
  let title = 'Freight Elevator';
  if (isCallPanel) {
    title = `Exterior Call - Depth ${panel_depth}`;
  } else if (isLayer) {
    title = `Freight Elevator - Depth ${panel_depth}`;
  }
  let blurb =
    'Pick a destination. A floor unlocks the next depth once its objective is fully complete.';
  if (isCallPanel) {
    blurb = 'This panel summons the elevator car to this depth.';
  } else if (isLayer) {
    blurb = `You're at depth ${panel_depth}. Complete this floor's objective to open the way down, or return to the surface.`;
  }

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

          {isLayer ? (
            <Button
              fluid
              icon="arrow-up"
              color="good"
              disabled={!!traveling}
              onClick={() => act('ascend')}
              mb={1}
            >
              Return to Surface
            </Button>
          ) : null}

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
                  onLock={() => act('lock_frontier')}
                  frontierLocked={!!frontier_locked}
                  frontierRollIn={frontier_roll_in}
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
  onLock: () => void;
  frontierLocked: boolean;
  frontierRollIn: number;
  traveling: boolean;
}) => {
  const d = props.depth;
  const hasGoals = (d.goals?.length ?? 0) > 0;
  const objective = d.stability ?? 0;
  const threshold = d.stability_threshold ?? 100;
  const complete = objective >= threshold;
  const satisfiedCount = d.goals?.filter((g) => !!g.satisfied).length ?? 0;
  const totalCount = d.goals?.length ?? 0;
  const danger = d.danger ?? 0;
  const rolling = !!d.rolling;
  const locked = props.frontierLocked;

  return (
    <Section
      title={
        d.archetype ? `Depth ${d.depth} — ${d.archetype}` : `Depth ${d.depth}`
      }
      buttons={
        <>
          {rolling ? (
            <Button
              icon={locked ? 'lock' : 'lock-open'}
              color={locked ? 'good' : 'average'}
              disabled={props.traveling}
              onClick={props.onLock}
              mr={1}
            >
              {locked ? 'Locked' : 'Lock In'}
            </Button>
          ) : null}
          <Button
            color={props.isCallPanel ? 'good' : complete ? 'good' : 'average'}
            disabled={props.traveling}
            onClick={props.onAction}
          >
            {props.isCallPanel ? 'Call Elevator' : 'Dispatch'}
          </Button>
        </>
      }
    >
      {d.archetype_desc ? (
        <Box color="label" italic mb={1} fontSize="0.9em">
          {d.archetype_desc}
        </Box>
      ) : null}
      {rolling ? (
        <Box
          mb={1}
          p={1}
          backgroundColor="rgba(0,0,0,0.25)"
          style={{ borderRadius: '2px' }}
        >
          {locked ? (
            <Box color="good">
              <Box inline bold mr={1}>
                Stratum locked.
              </Box>
              Held in place — descend to commit, or release to let it drift
              again.
            </Box>
          ) : (
            <Box color="average">
              <Box inline bold mr={1}>
                Stratum drifting.
              </Box>
              The formation below the bore is unstable
              {props.frontierRollIn > 0
                ? ` — shifts in ~${props.frontierRollIn}s`
                : ' — shifting now…'}
              . Lock it in to hold this one, or dispatch to commit.
            </Box>
          )}
        </Box>
      ) : null}

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
              {complete ? (
                <Box inline color="good" mr={1}>
                  ✓
                </Box>
              ) : null}
              Objective
            </Box>
            <Box inline color="label">
              {satisfiedCount} / {totalCount} goals complete
            </Box>
          </Box>
          <ProgressBar
            value={objective}
            minValue={0}
            maxValue={100}
            ranges={{
              good: [threshold, Infinity],
              average: [threshold / 2, threshold],
              bad: [-Infinity, threshold / 2],
            }}
          >
            {objective}%
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
