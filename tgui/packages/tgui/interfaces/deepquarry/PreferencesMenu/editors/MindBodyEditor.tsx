// DQAdd — Mind & Body specialty editor.
//
// Layout:
//   Top  — Age badge + two pool gauges (Body / Mind)
//   Left — Body: conditioning slider with tier notches + threshold perk grid
//   Right— Mind: department tabs (color-themed) + perk-tier graph for the active tree
//
// Visual language:
//   - Body theme: warm red (#C0392B); Mind tree themes come from the DM static data
//     (one per department, see /datum/perk_tree.color).
//   - Perk states: LOCKED (gated, dim), AVAILABLE (vibrant, "Take"), TAKEN (glowing
//     accent border, "Remove").
//   - Tooltips for full descriptions; cards show name + cost + a one-line gate hint.

import { useEffect, useMemo, useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  AnimatedNumber,
  Box,
  Button,
  Divider,
  Icon,
  ProgressBar,
  Section,
  Slider,
  Stack,
  Tooltip,
} from 'tgui-core/components';
import type { EditorProps } from './index';

// ─── Types ─────────────────────────────────────────────────────────────────────────────

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
  color: string;
  icon: string | null;
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

const BODY_ACCENT = '#C0392B';
const BODY_ACCENT_DIM = 'rgba(192, 57, 43, 0.18)';
const MIND_ACCENT = '#3498DB';
const MIND_ACCENT_DIM = 'rgba(52, 152, 219, 0.18)';

type Act = ReturnType<typeof useBackend>['act'];

const send = (act: Act, action: string, params: Record<string, unknown>) =>
  act('dq_editor_action', { editor: 'mind_body', action, params });

// ─── Root ──────────────────────────────────────────────────────────────────────────────

export const MindBodyEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as MindBodyData;
  const s = (staticData ?? {}) as MindBodyStatic;

  const mindTreeIds = useMemo(
    () =>
      Object.keys(s.trees ?? {})
        .filter((id) => id !== s.body_tree_id)
        .sort(
          (a, b) =>
            (s.trees[a]?.name ?? a).localeCompare(s.trees[b]?.name ?? b),
        ),
    [s.trees, s.body_tree_id],
  );

  const [activeMindTree, setActiveMindTree] = useState<string>('');
  useEffect(() => {
    if (!activeMindTree && mindTreeIds.length > 0) {
      // Prefer a tree the player has already invested in — feels right when they
      // re-open the editor mid-build.
      const invested = mindTreeIds.find((id) =>
        (s.trees[id]?.perks ?? []).some((p) => d.mind_perks.includes(p)),
      );
      setActiveMindTree(invested ?? mindTreeIds[0]);
    }
  }, [activeMindTree, mindTreeIds, s.trees, d.mind_perks]);

  if (!s.trees || !s.perks) return null;

  return (
    <Box>
      <Header data={d} />
      <Box mt={1}>
        <Stack>
          <Stack.Item grow basis="50%">
            <BodyPane data={d} staticData={s} act={act} />
          </Stack.Item>
          <Stack.Item grow basis="50%">
            <MindPane
              data={d}
              staticData={s}
              treeIds={mindTreeIds}
              activeTreeId={activeMindTree}
              setActiveTreeId={setActiveMindTree}
              act={act}
            />
          </Stack.Item>
        </Stack>
      </Box>
    </Box>
  );
};

// ─── Header strip ──────────────────────────────────────────────────────────────────────

const Header = ({ data: d }: { data: MindBodyData }) => (
  <Box
    p={1}
    style={{
      background:
        'linear-gradient(180deg, rgba(255,255,255,0.07), rgba(255,255,255,0.02))',
      borderRadius: '4px',
      border: '1px solid rgba(255,255,255,0.08)',
    }}
  >
    <Stack align="center">
      <Stack.Item>
        <AgeBadge age={d.age} />
      </Stack.Item>
      <Stack.Item grow>
        <Box ml={1.5}>
          <PoolBar
            label="Body"
            icon="dumbbell"
            color={BODY_ACCENT}
            spent={d.body_spent}
            pool={d.body_pool}
          />
          <Box mt={0.5}>
            <PoolBar
              label="Mind"
              icon="brain"
              color={MIND_ACCENT}
              spent={d.mind_spent}
              pool={d.mind_pool}
            />
          </Box>
        </Box>
      </Stack.Item>
    </Stack>
  </Box>
);

const AgeBadge = ({ age }: { age: number }) => (
  <Box
    style={{
      width: '64px',
      height: '64px',
      borderRadius: '50%',
      background:
        'radial-gradient(circle at 35% 30%, rgba(255,255,255,0.12), rgba(0,0,0,0.25))',
      border: '2px solid rgba(255,255,255,0.18)',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      boxShadow: 'inset 0 0 8px rgba(0,0,0,0.3)',
    }}
  >
    <Box fontSize="1.5em" bold style={{ lineHeight: '1em' }}>
      <AnimatedNumber value={age} />
    </Box>
    <Box fontSize="0.7em" color="label" style={{ letterSpacing: '0.1em' }}>
      YEARS
    </Box>
  </Box>
);

const PoolBar = ({
  label,
  icon,
  color,
  spent,
  pool,
}: {
  label: string;
  icon: string;
  color: string;
  spent: number;
  pool: number;
}) => {
  const remaining = pool - spent;
  return (
    <Stack align="center">
      <Stack.Item>
        <Box
          style={{
            width: '24px',
            display: 'flex',
            justifyContent: 'center',
          }}
        >
          <Icon name={icon} size={1.2} style={{ color }} />
        </Box>
      </Stack.Item>
      <Stack.Item>
        <Box
          style={{
            width: '52px',
            color,
            fontWeight: 'bold',
            letterSpacing: '0.05em',
          }}
        >
          {label}
        </Box>
      </Stack.Item>
      <Stack.Item grow>
        <ProgressBar
          value={pool > 0 ? spent / pool : 0}
          color={remaining < 0 ? 'bad' : undefined}
          style={{
            backgroundColor: 'rgba(0,0,0,0.35)',
          }}
        >
          <Box
            style={{
              color: '#fff',
              fontSize: '0.85em',
              textShadow: '0 0 3px rgba(0,0,0,0.8)',
            }}
          >
            {spent} / {pool}
          </Box>
        </ProgressBar>
      </Stack.Item>
      <Stack.Item>
        <Box
          ml={1}
          style={{
            minWidth: '70px',
            textAlign: 'right',
            fontSize: '0.9em',
            color: remaining < 0 ? '#E74C3C' : '#fff',
          }}
        >
          <AnimatedNumber value={Math.max(remaining, 0)} />
          <Box inline color="label" ml={0.5}>
            left
          </Box>
        </Box>
      </Stack.Item>
    </Stack>
  );
};

// ─── Body pane ─────────────────────────────────────────────────────────────────────────

const BodyPane = ({
  data: d,
  staticData: s,
  act,
}: {
  data: MindBodyData;
  staticData: MindBodyStatic;
  act: Act;
}) => {
  const tree = s.trees[s.body_tree_id];
  const remaining = d.body_pool - d.body_spent;
  // Linear cap is min of (pool - perks-spent) and body_max. Perks-spent = body_spent
  // minus the current linear contribution.
  const linearCap = Math.max(
    d.body_linear,
    Math.min(d.body_pool - (d.body_spent - d.body_linear), s.body_max),
  );

  return (
    <Section
      fill
      title={
        <Stack align="center">
          <Stack.Item>
            <Icon name="dumbbell" style={{ color: BODY_ACCENT }} />
          </Stack.Item>
          <Stack.Item>
            <Box ml={0.5} style={{ color: BODY_ACCENT }} bold>
              {tree?.name ?? 'Body'}
            </Box>
          </Stack.Item>
        </Stack>
      }
    >
      <Box color="label" mb={1} fontSize="0.9em">
        {tree?.description}
      </Box>

      <ConditioningBar
        value={d.body_linear}
        max={s.body_max}
        cap={linearCap}
        thresholds={s.thresholds}
        hpPerPoint={s.hp_per_point}
        slowdownPerPoint={s.slowdown_per_point}
        accent={BODY_ACCENT}
        act={act}
      />

      <Divider />

      <Box color="label" fontSize="0.85em" mb={1}>
        <Icon name="lock" mr={0.5} />
        Threshold perks unlock at{' '}
        <Box inline bold color="white">
          {s.thresholds.join(' / ')}
        </Box>{' '}
        conditioning.
      </Box>

      <Stack vertical>
        {tree?.perks
          .map((path) => s.perks[path])
          .filter((p): p is PerkMeta => Boolean(p))
          // Sort by threshold tier so the visual order matches the unlock progression.
          .sort((a, b) => a.threshold - b.threshold)
          .map((perk) => {
            const path = Object.keys(s.perks).find(
              (k) => s.perks[k] === perk,
            ) as string;
            const selected = d.body_perks.includes(path);
            const unlocked = d.body_linear >= perk.threshold;
            const affordable = selected || remaining >= perk.cost;
            const disabled = !selected && (!unlocked || !affordable);
            return (
              <Stack.Item key={path}>
                <PerkCard
                  perk={perk}
                  accent={BODY_ACCENT}
                  selected={selected}
                  disabled={disabled}
                  thresholdLabel={
                    perk.threshold > 0 ? `${perk.threshold} cond.` : null
                  }
                  gateHint={
                    !selected && !unlocked
                      ? `Needs ${perk.threshold} conditioning`
                      : !selected && !affordable
                        ? 'Not enough Body points'
                        : null
                  }
                  onClick={() =>
                    send(act, selected ? 'remove_perk' : 'add_perk', {
                      perk_path: path,
                    })
                  }
                />
              </Stack.Item>
            );
          })}
      </Stack>
    </Section>
  );
};

const ConditioningBar = ({
  value,
  max,
  cap,
  thresholds,
  hpPerPoint,
  slowdownPerPoint,
  accent,
  act,
}: {
  value: number;
  max: number;
  cap: number;
  thresholds: number[];
  hpPerPoint: number;
  slowdownPerPoint: number;
  accent: string;
  act: Act;
}) => (
  <Box mb={1}>
    <Stack align="center" mb={0.5}>
      <Stack.Item grow>
        <Box>
          <Box inline color="label">
            Conditioning
          </Box>{' '}
          <Box inline bold style={{ color: accent }}>
            {value}
          </Box>
          <Box inline color="label">
            {' '}
            / {cap}
          </Box>
        </Box>
      </Stack.Item>
      <Stack.Item>
        <Box fontSize="0.85em" color="label">
          +{value * hpPerPoint} HP · −
          {(value * slowdownPerPoint).toFixed(2)} slowdown
        </Box>
      </Stack.Item>
    </Stack>
    <Box style={{ position: 'relative' }}>
      <Slider
        value={value}
        minValue={0}
        maxValue={Math.max(cap, value, 1)}
        step={1}
        stepPixelSize={Math.max(280 / Math.max(max, 1), 16)}
        // Color the active fill with our body accent so it visually ties to the panel.
        color={accent}
        onChange={(_e: Event, newValue: number) =>
          send(act, 'set_body_points', { value: newValue })
        }
      >
        <Box style={{ color: '#fff', textShadow: '0 0 3px rgba(0,0,0,0.8)' }}>
          {value}
        </Box>
      </Slider>
      {/* Threshold notches sit above the slider; each marks where a tier perk unlocks. */}
      <Stack
        mt={0.25}
        style={{
          position: 'relative',
          height: '14px',
        }}
      >
        {thresholds.map((t) => (
          <Box
            key={t}
            style={{
              position: 'absolute',
              left: `${(t / Math.max(cap, 1)) * 100}%`,
              transform: 'translateX(-50%)',
              fontSize: '0.7em',
              color: value >= t ? accent : 'rgba(255,255,255,0.4)',
              fontWeight: value >= t ? 'bold' : 'normal',
              textShadow: '0 0 3px rgba(0,0,0,0.6)',
            }}
          >
            <Icon name={value >= t ? 'lock-open' : 'lock'} /> {t}
          </Box>
        ))}
      </Stack>
    </Box>
  </Box>
);

// ─── Mind pane ─────────────────────────────────────────────────────────────────────────

const MindPane = ({
  data: d,
  staticData: s,
  treeIds,
  activeTreeId,
  setActiveTreeId,
  act,
}: {
  data: MindBodyData;
  staticData: MindBodyStatic;
  treeIds: string[];
  activeTreeId: string;
  setActiveTreeId: (id: string) => void;
  act: Act;
}) => {
  const tree = s.trees[activeTreeId];
  const remaining = d.mind_pool - d.mind_spent;

  // Group perks by "tier" — perks with no requires are tier 1, those that require
  // something tier 1 are tier 2, etc. Keeps the visual flow top-down.
  const tiers = useMemo(() => {
    if (!tree) return [] as PerkMeta[][];
    const byPath: Record<string, PerkMeta> = {};
    for (const path of tree.perks) {
      const meta = s.perks[path];
      if (meta) byPath[path] = meta;
    }
    const tierFor = (path: string, visiting = new Set<string>()): number => {
      const meta = byPath[path];
      if (!meta) return 0;
      if (!meta.requires.length) return 0;
      if (visiting.has(path)) return 0; // cycle guard
      visiting.add(path);
      return 1 + Math.max(...meta.requires.map((r) => tierFor(r, visiting)));
    };
    const out: PerkMeta[][] = [];
    for (const path of Object.keys(byPath)) {
      const t = tierFor(path);
      if (!out[t]) out[t] = [];
      out[t].push(byPath[path]);
    }
    return out;
  }, [tree, s.perks]);

  return (
    <Section
      fill
      title={
        <Stack align="center">
          <Stack.Item>
            <Icon name="brain" style={{ color: MIND_ACCENT }} />
          </Stack.Item>
          <Stack.Item>
            <Box ml={0.5} style={{ color: MIND_ACCENT }} bold>
              Mind
            </Box>
          </Stack.Item>
        </Stack>
      }
    >
      <TreeTabRow
        trees={s.trees}
        treeIds={treeIds}
        activeTreeId={activeTreeId}
        setActiveTreeId={setActiveTreeId}
      />

      {tree && (
        <Box mt={1}>
          <Box
            p={1}
            style={{
              borderLeft: `3px solid ${tree.color}`,
              backgroundColor: 'rgba(255,255,255,0.03)',
              borderRadius: '0 3px 3px 0',
            }}
          >
            <Box bold style={{ color: tree.color }}>
              {tree.name}
            </Box>
            <Box fontSize="0.85em" color="label">
              {tree.description}
            </Box>
          </Box>

          <Box mt={1}>
            <Stack vertical>
              {tiers.map((perksAtTier, tier) => (
                <Stack.Item key={`tier-${tier}`}>
                  {tier > 0 && (
                    <Box
                      ml={2}
                      mb={0.25}
                      style={{
                        height: '12px',
                        borderLeft: `2px dashed ${tree.color}`,
                        opacity: 0.5,
                      }}
                    />
                  )}
                  {perksAtTier
                    .sort((a, b) => a.cost - b.cost)
                    .map((perk) => {
                      const path = tree.perks.find(
                        (p) => s.perks[p] === perk,
                      ) as string;
                      const selected = d.mind_perks.includes(path);
                      const requiresOk = perk.requires.every((r) =>
                        d.mind_perks.includes(r),
                      );
                      const affordable =
                        selected || remaining >= perk.cost;
                      const disabled =
                        !selected && (!requiresOk || !affordable);
                      return (
                        <Box key={path} mb={0.5}>
                          <PerkCard
                            perk={perk}
                            accent={tree.color}
                            selected={selected}
                            disabled={disabled}
                            thresholdLabel={null}
                            gateHint={
                              !selected && !requiresOk
                                ? `Requires ${perk.requires
                                    .map((r) => s.perks[r]?.name ?? r)
                                    .join(', ')}`
                                : !selected && !affordable
                                  ? 'Not enough Mind points'
                                  : null
                            }
                            onClick={() =>
                              send(
                                act,
                                selected ? 'remove_perk' : 'add_perk',
                                { perk_path: path },
                              )
                            }
                          />
                        </Box>
                      );
                    })}
                </Stack.Item>
              ))}
            </Stack>
          </Box>
        </Box>
      )}
    </Section>
  );
};

const TreeTabRow = ({
  trees,
  treeIds,
  activeTreeId,
  setActiveTreeId,
}: {
  trees: Record<string, TreeMeta>;
  treeIds: string[];
  activeTreeId: string;
  setActiveTreeId: (id: string) => void;
}) => (
  <Stack wrap>
    {treeIds.map((id) => {
      const tree = trees[id];
      if (!tree) return null;
      const isActive = id === activeTreeId;
      return (
        <Stack.Item key={id}>
          <Box
            mr={0.5}
            mb={0.5}
            onClick={() => setActiveTreeId(id)}
            style={{
              cursor: 'pointer',
              padding: '4px 10px',
              borderRadius: '14px',
              backgroundColor: isActive
                ? tree.color
                : 'rgba(255,255,255,0.05)',
              border: `1px solid ${isActive ? tree.color : 'rgba(255,255,255,0.12)'}`,
              color: isActive ? '#fff' : tree.color,
              fontWeight: isActive ? 'bold' : 'normal',
              fontSize: '0.85em',
              transition: 'background-color 120ms, color 120ms',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '6px',
              boxShadow: isActive
                ? `0 0 6px ${tree.color}66`
                : 'none',
            }}
          >
            {tree.icon && <Icon name={tree.icon} />}
            {tree.name}
          </Box>
        </Stack.Item>
      );
    })}
  </Stack>
);

// ─── Shared perk card ─────────────────────────────────────────────────────────────────

const PerkCard = ({
  perk,
  accent,
  selected,
  disabled,
  thresholdLabel,
  gateHint,
  onClick,
}: {
  perk: PerkMeta;
  accent: string;
  selected: boolean;
  disabled: boolean;
  thresholdLabel: string | null;
  gateHint: string | null;
  onClick: () => void;
}) => {
  const background = selected
    ? `linear-gradient(90deg, ${accent}33, ${accent}11)`
    : disabled
      ? 'rgba(255,255,255,0.02)'
      : 'rgba(255,255,255,0.04)';
  const border = selected
    ? `1px solid ${accent}`
    : disabled
      ? '1px solid rgba(255,255,255,0.06)'
      : `1px solid ${accent}55`;
  return (
    <Tooltip content={<Box style={{ maxWidth: '280px' }}>{perk.desc}</Box>}>
      <Box
        px={1}
        py={0.5}
        style={{
          background,
          border,
          borderRadius: '4px',
          opacity: disabled ? 0.5 : 1,
          transition: 'all 120ms',
          boxShadow: selected ? `0 0 6px ${accent}55` : 'none',
        }}
      >
        <Stack align="center">
          <Stack.Item grow>
            <Box>
              {selected && (
                <Icon
                  name="check-circle"
                  mr={0.5}
                  style={{ color: accent }}
                />
              )}
              <Box inline bold>
                {perk.name}
              </Box>
              <Box
                inline
                ml={1}
                style={{
                  fontSize: '0.75em',
                  padding: '1px 6px',
                  borderRadius: '8px',
                  backgroundColor: `${accent}33`,
                  color: accent,
                  fontWeight: 'bold',
                }}
              >
                {perk.cost} pt{perk.cost === 1 ? '' : 's'}
              </Box>
              {thresholdLabel && (
                <Box
                  inline
                  ml={0.5}
                  style={{
                    fontSize: '0.7em',
                    color: 'rgba(255,255,255,0.5)',
                  }}
                >
                  · {thresholdLabel}
                </Box>
              )}
            </Box>
            <Box
              fontSize="0.8em"
              color="label"
              style={{
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                maxWidth: '320px',
              }}
            >
              {perk.desc}
            </Box>
            {gateHint && (
              <Box fontSize="0.8em" italic style={{ color: '#E74C3C' }}>
                <Icon name="triangle-exclamation" mr={0.5} />
                {gateHint}
              </Box>
            )}
          </Stack.Item>
          <Stack.Item>
            <Button
              icon={selected ? 'xmark' : 'plus'}
              color={selected ? 'bad' : disabled ? undefined : 'good'}
              disabled={disabled}
              onClick={onClick}
            >
              {selected ? 'Remove' : 'Take'}
            </Button>
          </Stack.Item>
        </Stack>
      </Box>
    </Tooltip>
  );
};
