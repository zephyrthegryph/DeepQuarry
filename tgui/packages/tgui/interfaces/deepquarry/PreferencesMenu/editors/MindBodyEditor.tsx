// DQAdd — Mind/Body specialty editor. Two-pane layout:
//   left  — Body slider (linear allocation) + Body threshold-perk grid
//   right — Mind tree dropdown + Mind perk grid
// Header shows age + each pool's spent/total. Pools are derived from age on the DM side
// so the header re-renders automatically when the user changes their birth year elsewhere.

import { useMemo, useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Section,
  Slider,
  Stack,
} from 'tgui-core/components';
import type { EditorProps } from './index';

type PerkMeta = {
  name: string;
  desc: string;
  cost: number;
  category: 'body' | 'mind';
  tree: string;
  threshold: number;
  requires: string[];
};

type TreeMeta = {
  id: string;
  name: string;
  description: string;
  perks: string[];
};

type MindBodyData = {
  age: number;
  body_pool: number;
  mind_pool: number;
  body_linear: number;
  body_spent: number;
  mind_spent: number;
  body_perks: string[];
  mind_perks: string[];
};

type MindBodyStatic = {
  trees: Record<string, TreeMeta>;
  perks: Record<string, PerkMeta>;
  body_tree_id: string;
  body_max: number;
  hp_per_point: number;
  slowdown_per_point: number;
  thresholds: number[];
};

const send = (
  act: ReturnType<typeof useBackend>['act'],
  action: string,
  params: Record<string, unknown>,
) => act('dq_editor_action', { editor: 'mind_body', action, params });

export const MindBodyEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as MindBodyData;
  const s = (staticData ?? {}) as MindBodyStatic;

  // Mind tree dropdowns persist across re-renders even though the React tree is rebuilt
  // each backend tick. Default to the first non-body tree (sorted by id for stability).
  const mindTreeIds = useMemo(
    () =>
      Object.keys(s.trees ?? {})
        .filter((id) => id !== s.body_tree_id)
        .sort(),
    [s.trees, s.body_tree_id],
  );
  const [activeMindTree, setActiveMindTree] = useState<string>(
    mindTreeIds[0] ?? '',
  );

  if (!s.trees || !s.perks) return null;

  const bodyRemaining = d.body_pool - d.body_spent;
  const mindRemaining = d.mind_pool - d.mind_spent;
  const bodyTree = s.trees[s.body_tree_id];
  const mindTree = s.trees[activeMindTree];

  return (
    <Box>
      <Header
        age={d.age}
        bodySpent={d.body_spent}
        bodyPool={d.body_pool}
        mindSpent={d.mind_spent}
        mindPool={d.mind_pool}
      />
      <Stack mt={1}>
        <Stack.Item grow basis="50%">
          <BodyPane
            d={d}
            s={s}
            tree={bodyTree}
            remaining={bodyRemaining}
            act={act}
          />
        </Stack.Item>
        <Stack.Item grow basis="50%">
          <MindPane
            d={d}
            s={s}
            treeIds={mindTreeIds}
            activeTreeId={activeMindTree}
            setActiveTreeId={setActiveMindTree}
            tree={mindTree}
            remaining={mindRemaining}
            act={act}
          />
        </Stack.Item>
      </Stack>
    </Box>
  );
};

type HeaderProps = {
  age: number;
  bodySpent: number;
  bodyPool: number;
  mindSpent: number;
  mindPool: number;
};

const Header = ({
  age,
  bodySpent,
  bodyPool,
  mindSpent,
  mindPool,
}: HeaderProps) => {
  const bodyRemaining = bodyPool - bodySpent;
  const mindRemaining = mindPool - mindSpent;
  return (
    <Box
      px={1}
      py={0.5}
      style={{
        backgroundColor: 'rgba(255,255,255,0.05)',
        borderRadius: '2px',
      }}
    >
      <Stack align="center">
        <Stack.Item>
          <Box color="label">Age</Box>
          <Box bold>{age}</Box>
        </Stack.Item>
        <Stack.Item grow>
          <Box ml={2}>
            <Box inline color="label">
              Body
            </Box>{' '}
            <Box inline color={bodyRemaining < 0 ? 'bad' : 'good'} bold>
              {bodyRemaining}
            </Box>{' '}
            left ({bodySpent}/{bodyPool})
          </Box>
          <Box ml={2}>
            <Box inline color="label">
              Mind
            </Box>{' '}
            <Box inline color={mindRemaining < 0 ? 'bad' : 'good'} bold>
              {mindRemaining}
            </Box>{' '}
            left ({mindSpent}/{mindPool})
          </Box>
        </Stack.Item>
      </Stack>
    </Box>
  );
};

type BodyPaneProps = {
  d: MindBodyData;
  s: MindBodyStatic;
  tree: TreeMeta;
  remaining: number;
  act: ReturnType<typeof useBackend>['act'];
};

const BodyPane = ({ d, s, tree, remaining, act }: BodyPaneProps) => {
  const linearCap = Math.min(
    d.body_pool - (d.body_spent - d.body_linear), // pool minus everything-but-linear
    s.body_max,
  );
  return (
    <Section title={tree?.name ?? 'Body'} fill>
      <Box color="label" mb={1}>
        {tree?.description}
      </Box>
      <Stack vertical>
        <Stack.Item>
          <Box mb={0.5}>
            <Box inline color="label">
              Conditioning:
            </Box>{' '}
            <Box inline bold>
              {d.body_linear}
            </Box>{' '}
            pts → +{d.body_linear * s.hp_per_point} HP, −
            {(d.body_linear * s.slowdown_per_point).toFixed(2)} slowdown
          </Box>
          <Slider
            value={d.body_linear}
            minValue={0}
            maxValue={Math.max(d.body_linear, linearCap)}
            step={1}
            stepPixelSize={20}
            onChange={(_e, value: number) =>
              send(act, 'set_body_points', { value })
            }
          />
        </Stack.Item>
        <Stack.Item mt={1}>
          <Box color="label" mb={0.5}>
            Threshold perks (unlock at {s.thresholds.join(' / ')} conditioning)
          </Box>
          {tree?.perks.map((path) => {
            const perk = s.perks[path];
            if (!perk) return null;
            const selected = d.body_perks.includes(path);
            const unlocked = d.body_linear >= perk.threshold;
            const affordable = remaining >= perk.cost;
            return (
              <PerkRow
                key={path}
                path={path}
                perk={perk}
                selected={selected}
                disabled={!selected && (!unlocked || !affordable)}
                gateNote={
                  !selected && !unlocked
                    ? `Needs ${perk.threshold} conditioning`
                    : !selected && !affordable
                      ? 'Not enough Body points'
                      : ''
                }
                onClick={() =>
                  send(act, selected ? 'remove_perk' : 'add_perk', {
                    perk_path: path,
                  })
                }
              />
            );
          })}
        </Stack.Item>
      </Stack>
    </Section>
  );
};

type MindPaneProps = {
  d: MindBodyData;
  s: MindBodyStatic;
  treeIds: string[];
  activeTreeId: string;
  setActiveTreeId: (id: string) => void;
  tree: TreeMeta | undefined;
  remaining: number;
  act: ReturnType<typeof useBackend>['act'];
};

const MindPane = ({
  d,
  s,
  treeIds,
  activeTreeId,
  setActiveTreeId,
  tree,
  remaining,
  act,
}: MindPaneProps) => {
  return (
    <Section title="Mind" fill>
      <Stack vertical>
        <Stack.Item>
          <Stack wrap>
            {treeIds.map((id) => (
              <Stack.Item key={id}>
                <Button
                  selected={id === activeTreeId}
                  onClick={() => setActiveTreeId(id)}
                >
                  {s.trees[id]?.name ?? id}
                </Button>
              </Stack.Item>
            ))}
          </Stack>
        </Stack.Item>
        {tree && (
          <Stack.Item>
            <Box color="label" mb={1}>
              {tree.description}
            </Box>
            {tree.perks.map((path) => {
              const perk = s.perks[path];
              if (!perk) return null;
              const selected = d.mind_perks.includes(path);
              const requiresOk = perk.requires.every((r) =>
                d.mind_perks.includes(r),
              );
              const affordable = remaining >= perk.cost;
              return (
                <PerkRow
                  key={path}
                  path={path}
                  perk={perk}
                  selected={selected}
                  disabled={!selected && (!requiresOk || !affordable)}
                  gateNote={
                    !selected && !requiresOk
                      ? `Requires ${perk.requires.map((r) => s.perks[r]?.name ?? r).join(', ')}`
                      : !selected && !affordable
                        ? 'Not enough Mind points'
                        : ''
                  }
                  onClick={() =>
                    send(act, selected ? 'remove_perk' : 'add_perk', {
                      perk_path: path,
                    })
                  }
                />
              );
            })}
          </Stack.Item>
        )}
      </Stack>
    </Section>
  );
};

type PerkRowProps = {
  path: string;
  perk: PerkMeta;
  selected: boolean;
  disabled: boolean;
  gateNote: string;
  onClick: () => void;
};

const PerkRow = ({
  perk,
  selected,
  disabled,
  gateNote,
  onClick,
}: PerkRowProps) => (
  <Box
    mb={0.5}
    px={1}
    py={0.5}
    style={{
      backgroundColor: selected
        ? 'rgba(80,160,80,0.15)'
        : 'rgba(255,255,255,0.03)',
      borderRadius: '2px',
      borderLeft: selected
        ? '3px solid rgba(80,160,80,0.8)'
        : '3px solid transparent',
      opacity: disabled ? 0.5 : 1,
    }}
  >
    <Stack align="center">
      <Stack.Item grow>
        <Box bold>
          {perk.name} <Box inline color="label">({perk.cost})</Box>
        </Box>
        <Box fontSize="0.9em" color="label">
          {perk.desc}
        </Box>
        {gateNote && (
          <Box fontSize="0.85em" color="bad" italic>
            {gateNote}
          </Box>
        )}
      </Stack.Item>
      <Stack.Item>
        <Button
          color={selected ? 'bad' : 'good'}
          disabled={disabled}
          onClick={onClick}
        >
          {selected ? 'Remove' : 'Take'}
        </Button>
      </Stack.Item>
    </Stack>
  </Box>
);
