// DQAdd — Mind & Body specialty editor.
//
// Layout claims its container's full height (registered in DQCharacterSetup's
// FULL_HEIGHT_EDITORS) so we can manage our own pane scrolling: header on top
// (fixed), then two side-by-side panes each with their own internal scroll.
//
// Visual language:
//   - Body pane: four themed sub-trees (Strength, Vigor, Speed, Endurance) all
//     drawing from the same Body pool. A Conditioning slider sits above the
//     tabs and provides the per-point linear stat tweak + the threshold gate
//     that unlocks tier perks.
//   - Mind pane: per-department perk trees, also tab-switched.
//   - Tree chips: color-themed, animated hover, pick-count badge.
//   - Perk cards: whole card is the click target (no inner button). Card body
//     always wraps cleanly; full text inline (no tooltip wrapper that ate clicks
//     on a previous iteration).
//   - State icons: circle / circle-check / lock — picked / available / locked.

import { useEffect, useMemo, useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  AnimatedNumber,
  Box,
  Divider,
  Icon,
  ProgressBar,
  Section,
  Slider,
  Stack,
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
  body_tree_ids: string[];
  body_max: number;
  hp_per_point: number;
  slowdown_per_point: number;
  thresholds: number[];
};

const BODY_ACCENT = '#C0392B';
const MIND_ACCENT = '#3498DB';
const BAD = '#E74C3C';

type Act = ReturnType<typeof useBackend>['act'];

const send = (act: Act, action: string, params: Record<string, unknown>) =>
  act('dq_editor_action', { editor: 'mind_body', action, params });

const pathFor = (
  perksDict: Record<string, PerkMeta>,
  perk: PerkMeta,
): string | null => {
  for (const k in perksDict) {
    if (perksDict[k] === perk) return k;
  }
  return null;
};

// ─── Root ──────────────────────────────────────────────────────────────────────────────

export const MindBodyEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as MindBodyData;
  const s = (staticData ?? {}) as MindBodyStatic;

  const bodyTreeIds = useMemo(
    () => (s.body_tree_ids ?? []).filter((id) => s.trees?.[id]),
    [s.body_tree_ids, s.trees],
  );

  const mindTreeIds = useMemo(() => {
    if (!s.trees) return [];
    const bodySet = new Set(bodyTreeIds);
    return Object.keys(s.trees)
      .filter((id) => !bodySet.has(id))
      .sort((a, b) =>
        (s.trees[a]?.name ?? a).localeCompare(s.trees[b]?.name ?? b),
      );
  }, [s.trees, bodyTreeIds]);

  // Default-active tabs. Prefer a tree the player has invested in; otherwise
  // first-in-list. The picksByTree memo is shared so both panes can compute
  // independently from the same source of truth.
  const picksByTree = useMemo(() => {
    const out: Record<string, number> = {};
    for (const path of [...d.body_perks, ...d.mind_perks]) {
      const meta = s.perks?.[path];
      if (meta) out[meta.tree] = (out[meta.tree] ?? 0) + 1;
    }
    return out;
  }, [d.body_perks, d.mind_perks, s.perks]);

  const [activeBodyTree, setActiveBodyTree] = useState<string>('');
  useEffect(() => {
    if (!activeBodyTree && bodyTreeIds.length > 0) {
      const invested = bodyTreeIds.find((id) => (picksByTree[id] ?? 0) > 0);
      setActiveBodyTree(invested ?? bodyTreeIds[0]);
    }
  }, [activeBodyTree, bodyTreeIds, picksByTree]);

  const [activeMindTree, setActiveMindTree] = useState<string>('');
  useEffect(() => {
    if (!activeMindTree && mindTreeIds.length > 0) {
      const invested = mindTreeIds.find((id) => (picksByTree[id] ?? 0) > 0);
      setActiveMindTree(invested ?? mindTreeIds[0]);
    }
  }, [activeMindTree, mindTreeIds, picksByTree]);

  if (!s.trees || !s.perks) return null;

  return (
    <Box
      style={{
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      <Header data={d} />
      <Box
        mt={0.5}
        style={{
          flex: 1,
          minHeight: 0,
          display: 'flex',
          flexDirection: 'row',
        }}
      >
        <Box style={{ flex: 1, minWidth: 0, display: 'flex' }}>
          <BodyPane
            data={d}
            staticData={s}
            treeIds={bodyTreeIds}
            activeTreeId={activeBodyTree}
            setActiveTreeId={setActiveBodyTree}
            picksByTree={picksByTree}
            act={act}
          />
        </Box>
        <Box ml={0.5} style={{ flex: 1, minWidth: 0, display: 'flex' }}>
          <MindPane
            data={d}
            staticData={s}
            treeIds={mindTreeIds}
            activeTreeId={activeMindTree}
            setActiveTreeId={setActiveMindTree}
            picksByTree={picksByTree}
            act={act}
          />
        </Box>
      </Box>
    </Box>
  );
};

// ─── Header strip ──────────────────────────────────────────────────────────────────────

const Header = ({ data: d }: { data: MindBodyData }) => (
  <Box
    px={1}
    py={0.5}
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
        <Box ml={1}>
          <PoolRow
            label="Body"
            icon="dumbbell"
            color={BODY_ACCENT}
            spent={d.body_spent}
            pool={d.body_pool}
          />
          <Box mt={0.25}>
            <PoolRow
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
      width: '52px',
      height: '52px',
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
    <Box fontSize="1.25em" bold style={{ lineHeight: '1em' }}>
      <AnimatedNumber value={age} />
    </Box>
    <Box
      fontSize="0.62em"
      color="label"
      style={{ letterSpacing: '0.1em', marginTop: '2px' }}
    >
      YEARS
    </Box>
  </Box>
);

const PoolRow = ({
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
  const isOver = remaining < 0;
  return (
    <Stack align="center">
      <Stack.Item>
        <Box style={{ width: '20px', textAlign: 'center' }}>
          <Icon name={icon} style={{ color }} />
        </Box>
      </Stack.Item>
      <Stack.Item>
        <Box
          style={{
            width: '44px',
            color,
            fontWeight: 'bold',
            letterSpacing: '0.05em',
            fontSize: '0.9em',
          }}
        >
          {label}
        </Box>
      </Stack.Item>
      <Stack.Item grow>
        <ProgressBar
          value={pool > 0 ? spent / pool : 0}
          color={isOver ? 'bad' : color}
          style={{
            backgroundColor: 'rgba(0,0,0,0.35)',
          }}
        >
          <Box
            style={{
              color: '#fff',
              fontSize: '0.78em',
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
            minWidth: '64px',
            textAlign: 'right',
            fontSize: '0.85em',
            color: isOver ? BAD : '#fff',
            fontWeight: 'bold',
          }}
        >
          <AnimatedNumber value={Math.max(remaining, 0)} />
          <Box inline color="label" ml={0.5} style={{ fontWeight: 'normal' }}>
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
  treeIds,
  activeTreeId,
  setActiveTreeId,
  picksByTree,
  act,
}: {
  data: MindBodyData;
  staticData: MindBodyStatic;
  treeIds: string[];
  activeTreeId: string;
  setActiveTreeId: (id: string) => void;
  picksByTree: Record<string, number>;
  act: Act;
}) => {
  const tree = s.trees[activeTreeId];
  const remaining = d.body_pool - d.body_spent;
  // Linear cap = pool minus perks-spent. Perks-spent = body_spent − current linear.
  const linearCap = Math.max(
    d.body_linear,
    Math.min(d.body_pool - (d.body_spent - d.body_linear), s.body_max),
  );

  return (
    <Section
      fill
      scrollable
      style={{ flex: 1, display: 'flex' }}
      title={
        <PaneTitle icon="dumbbell" color={BODY_ACCENT} label="Body" />
      }
    >
      <ConditioningBar
        value={d.body_linear}
        cap={linearCap}
        thresholds={s.thresholds}
        hpPerPoint={s.hp_per_point}
        slowdownPerPoint={s.slowdown_per_point}
        accent={BODY_ACCENT}
        act={act}
      />

      <Divider />

      <TreeTabRow
        trees={s.trees}
        treeIds={treeIds}
        activeTreeId={activeTreeId}
        setActiveTreeId={setActiveTreeId}
        picksByTree={picksByTree}
      />

      {tree && (
        <Box mt={1}>
          <PerkList
            tree={tree}
            perksDict={s.perks}
            selectedPaths={d.body_perks}
            remaining={remaining}
            linear={d.body_linear}
            act={act}
          />
        </Box>
      )}
    </Section>
  );
};

const ConditioningBar = ({
  value,
  cap,
  thresholds,
  hpPerPoint,
  slowdownPerPoint,
  accent,
  act,
}: {
  value: number;
  cap: number;
  thresholds: number[];
  hpPerPoint: number;
  slowdownPerPoint: number;
  accent: string;
  act: Act;
}) => {
  const denom = Math.max(cap, value, 1);
  // Local draft so the slider visually tracks the cursor even before the server
  // round-trip lands; we still write through to the server on each onChange tick.
  // External updates (constraint refits, age change) clobber the draft via the
  // useEffect sync below.
  const [draft, setDraft] = useState(value);
  useEffect(() => setDraft(value), [value]);

  return (
    <Box mb={1}>
      <Stack align="center" mb={0.25}>
        <Stack.Item grow>
          <Box>
            <Icon name="dumbbell" mr={0.5} style={{ color: accent }} />
            <Box inline color="label">
              Conditioning
            </Box>{' '}
            <Box inline bold style={{ color: accent }}>
              <AnimatedNumber value={draft} />
            </Box>
            <Box inline color="label">
              {' '}
              / {cap}
            </Box>
          </Box>
        </Stack.Item>
        <Stack.Item>
          <Box fontSize="0.82em" color="label">
            <Icon name="heart-pulse" mr={0.25} style={{ color: accent }} />
            +{draft * hpPerPoint} HP
            <Box inline mx={0.5} color="label">
              ·
            </Box>
            <Icon name="person-running" mr={0.25} style={{ color: accent }} />
            −{(draft * slowdownPerPoint).toFixed(2)} slowdown
          </Box>
        </Stack.Item>
      </Stack>
      <Box style={{ position: 'relative', paddingBottom: '16px' }}>
        <Slider
          value={draft}
          minValue={0}
          maxValue={Math.max(cap, value, 1)}
          step={1}
          // stepPixelSize controls how many pixels of cursor drag = one step.
          // Default (1) makes a 14-step slider span only 14 pixels of cursor
          // travel — the cursor and thumb "don't match up". 22 ≈ a 300-ish-px
          // wide slider divided across 14 steps, which is close to what the
          // Body pane gives us at the default window size. tickWhileDragging
          // intentionally off — it would fire a server roundtrip per intermediate
          // step and the visible "lag" of those roundtrips reads as drag lag.
          // Slider's own internal drag preview keeps the thumb on the cursor.
          stepPixelSize={22}
          color={accent}
          onChange={(_e: Event, newValue: number) => {
            setDraft(newValue);
            send(act, 'set_body_points', { value: newValue });
          }}
        >
          <Box style={{ color: '#fff', textShadow: '0 0 3px rgba(0,0,0,0.8)' }}>
            {draft}
          </Box>
        </Slider>
        {thresholds.map((t) => {
          const active = draft >= t;
          const pct = (t / denom) * 100;
          return (
            <Box
              key={t}
              style={{
                position: 'absolute',
                left: `${pct}%`,
                bottom: 0,
                transform: 'translateX(-50%)',
                fontSize: '0.7em',
                color: active ? accent : 'rgba(255,255,255,0.45)',
                fontWeight: active ? 'bold' : 'normal',
                textShadow: '0 0 3px rgba(0,0,0,0.7)',
                whiteSpace: 'nowrap',
              }}
            >
              <Icon name={active ? 'lock-open' : 'lock'} mr={0.25} />
              {t}
            </Box>
          );
        })}
      </Box>
    </Box>
  );
};

// ─── Mind pane ─────────────────────────────────────────────────────────────────────────

const MindPane = ({
  data: d,
  staticData: s,
  treeIds,
  activeTreeId,
  setActiveTreeId,
  picksByTree,
  act,
}: {
  data: MindBodyData;
  staticData: MindBodyStatic;
  treeIds: string[];
  activeTreeId: string;
  setActiveTreeId: (id: string) => void;
  picksByTree: Record<string, number>;
  act: Act;
}) => {
  const tree = s.trees[activeTreeId];
  const remaining = d.mind_pool - d.mind_spent;

  return (
    <Section
      fill
      scrollable
      style={{ flex: 1, display: 'flex' }}
      title={<PaneTitle icon="brain" color={MIND_ACCENT} label="Mind" />}
    >
      <TreeTabRow
        trees={s.trees}
        treeIds={treeIds}
        activeTreeId={activeTreeId}
        setActiveTreeId={setActiveTreeId}
        picksByTree={picksByTree}
      />

      {tree && (
        <Box mt={1}>
          <TreeBlurb tree={tree} pickedHere={picksByTree[tree.id] ?? 0} />
          <Box mt={1}>
            <PerkList
              tree={tree}
              perksDict={s.perks}
              selectedPaths={d.mind_perks}
              remaining={remaining}
              linear={null}
              act={act}
            />
          </Box>
        </Box>
      )}
    </Section>
  );
};

const TreeBlurb = ({
  tree,
  pickedHere,
}: {
  tree: TreeMeta;
  pickedHere: number;
}) => {
  if (!tree.description) return null;
  return (
    <Box
      px={1}
      py={0.5}
      style={{
        borderLeft: `3px solid ${tree.color}`,
        backgroundColor: 'rgba(255,255,255,0.03)',
        borderRadius: '0 3px 3px 0',
      }}
    >
      <Stack align="center">
        <Stack.Item grow>
          <Box bold style={{ color: tree.color }}>
            {tree.icon && (
              <Icon name={tree.icon} mr={0.5} style={{ color: tree.color }} />
            )}
            {tree.name}
          </Box>
          <Box fontSize="0.82em" color="label">
            {tree.description}
          </Box>
        </Stack.Item>
        {pickedHere > 0 && (
          <Stack.Item>
            <Box
              style={{
                padding: '2px 8px',
                borderRadius: '10px',
                backgroundColor: `${tree.color}33`,
                color: tree.color,
                fontWeight: 'bold',
                fontSize: '0.78em',
                whiteSpace: 'nowrap',
              }}
            >
              <Icon name="check" mr={0.25} />
              {pickedHere} taken
            </Box>
          </Stack.Item>
        )}
      </Stack>
    </Box>
  );
};

// ─── Shared perk list (grouped by tier within a single tree) ──────────────────────────

const PerkList = ({
  tree,
  perksDict,
  selectedPaths,
  remaining,
  linear,
  act,
}: {
  tree: TreeMeta;
  perksDict: Record<string, PerkMeta>;
  selectedPaths: string[];
  remaining: number;
  /// For Body trees: current linear Conditioning value, used to evaluate per-perk
  /// threshold gates. Pass null for Mind trees (no threshold concept).
  linear: number | null;
  act: Act;
}) => {
  // Group the tree's perks by dependency depth.
  const tiers = useMemo(() => {
    const byPath: Record<string, PerkMeta> = {};
    for (const path of tree.perks) {
      const meta = perksDict[path];
      if (meta) byPath[path] = meta;
    }
    const tierFor = (path: string, visiting = new Set<string>()): number => {
      const meta = byPath[path];
      if (!meta) return 0;
      if (!meta.requires.length) return 0;
      if (visiting.has(path)) return 0;
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
  }, [tree, perksDict]);

  return (
    <Stack vertical>
      {tiers.map((perksAtTier, tier) => (
        <Stack.Item key={`tier-${tier}`}>
          {tier > 0 && (
            <Box
              ml={2}
              mb={0.25}
              style={{
                height: '8px',
                borderLeft: `2px dashed ${tree.color}`,
                opacity: 0.5,
              }}
            />
          )}
          {perksAtTier
            .sort((a, b) => a.cost - b.cost)
            .map((perk) => {
              const path = pathFor(perksDict, perk);
              if (!path) return null;
              const selected = selectedPaths.includes(path);
              const requiresOk = perk.requires.every((r) =>
                selectedPaths.includes(r),
              );
              const unlocked =
                linear === null || perk.threshold === 0 || linear >= perk.threshold;
              const affordable = selected || remaining >= perk.cost;
              const disabled =
                !selected && (!requiresOk || !unlocked || !affordable);
              return (
                <Box key={path} mb={0.5}>
                  <PerkCard
                    perk={perk}
                    accent={tree.color}
                    selected={selected}
                    disabled={disabled}
                    badge={
                      perk.threshold > 0
                        ? {
                            icon: unlocked ? 'lock-open' : 'lock',
                            text: `${perk.threshold}`,
                          }
                        : null
                    }
                    gateHint={
                      !selected && !unlocked
                        ? `Needs ${perk.threshold} Conditioning`
                        : !selected && !requiresOk
                          ? `Requires ${perk.requires
                              .map((r) => perksDict[r]?.name ?? r)
                              .join(', ')}`
                          : !selected && !affordable
                            ? 'Not enough points'
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
  );
};

// ─── Tree tabs ────────────────────────────────────────────────────────────────────────

const TreeTabRow = ({
  trees,
  treeIds,
  activeTreeId,
  setActiveTreeId,
  picksByTree,
}: {
  trees: Record<string, TreeMeta>;
  treeIds: string[];
  activeTreeId: string;
  setActiveTreeId: (id: string) => void;
  picksByTree: Record<string, number>;
}) => (
  <Stack wrap>
    {treeIds.map((id) => {
      const tree = trees[id];
      if (!tree) return null;
      const isActive = id === activeTreeId;
      const picks = picksByTree[id] ?? 0;
      return (
        <Stack.Item key={id}>
          <TreeChip
            tree={tree}
            isActive={isActive}
            picks={picks}
            onClick={() => setActiveTreeId(id)}
          />
        </Stack.Item>
      );
    })}
  </Stack>
);

const TreeChip = ({
  tree,
  isActive,
  picks,
  onClick,
}: {
  tree: TreeMeta;
  isActive: boolean;
  picks: number;
  onClick: () => void;
}) => {
  const [hover, setHover] = useState(false);
  const bg = isActive
    ? tree.color
    : hover
      ? `${tree.color}33`
      : 'rgba(255,255,255,0.05)';
  const fg = isActive ? '#fff' : tree.color;
  const border = isActive
    ? tree.color
    : hover
      ? tree.color
      : 'rgba(255,255,255,0.12)';
  return (
    <Box
      mr={0.5}
      mb={0.5}
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        cursor: 'pointer',
        padding: '3px 9px',
        borderRadius: '14px',
        backgroundColor: bg,
        border: `1px solid ${border}`,
        color: fg,
        fontWeight: isActive || picks > 0 ? 'bold' : 'normal',
        fontSize: '0.85em',
        transition: 'background-color 120ms, color 120ms, border-color 120ms',
        display: 'inline-flex',
        alignItems: 'center',
        gap: '6px',
        boxShadow: isActive ? `0 0 6px ${tree.color}66` : 'none',
      }}
    >
      {tree.icon && <Icon name={tree.icon} />}
      {tree.name}
      {picks > 0 && (
        <Box
          style={{
            backgroundColor: isActive
              ? 'rgba(255,255,255,0.25)'
              : `${tree.color}44`,
            borderRadius: '8px',
            padding: '0 5px',
            fontSize: '0.85em',
            fontWeight: 'bold',
          }}
        >
          {picks}
        </Box>
      )}
    </Box>
  );
};

// ─── Pane title ──────────────────────────────────────────────────────────────────────

const PaneTitle = ({
  icon,
  color,
  label,
}: {
  icon: string;
  color: string;
  label: string;
}) => (
  <Stack align="center">
    <Stack.Item>
      <Icon name={icon} style={{ color }} />
    </Stack.Item>
    <Stack.Item>
      <Box ml={0.5} style={{ color }} bold>
        {label}
      </Box>
    </Stack.Item>
  </Stack>
);

// ─── Perk card ────────────────────────────────────────────────────────────────────────

type PerkCardBadge = {
  icon: string;
  text: string;
};

const PerkCard = ({
  perk,
  accent,
  selected,
  disabled,
  badge,
  gateHint,
  onClick,
}: {
  perk: PerkMeta;
  accent: string;
  selected: boolean;
  disabled: boolean;
  badge: PerkCardBadge | null;
  gateHint: string | null;
  onClick: () => void;
}) => {
  const [hover, setHover] = useState(false);
  const clickable = selected || !disabled;
  const background = selected
    ? `linear-gradient(90deg, ${accent}44, ${accent}11)`
    : disabled
      ? 'rgba(255,255,255,0.02)'
      : hover
        ? `linear-gradient(90deg, ${accent}22, transparent)`
        : 'rgba(255,255,255,0.04)';
  const border = selected
    ? `1px solid ${accent}`
    : disabled
      ? '1px solid rgba(255,255,255,0.06)'
      : hover
        ? `1px solid ${accent}`
        : `1px solid ${accent}55`;
  return (
    <Box
      onClick={clickable ? onClick : undefined}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      px={1}
      py={0.5}
      style={{
        background,
        border,
        borderRadius: '4px',
        opacity: disabled ? 0.55 : 1,
        transition: 'all 120ms',
        boxShadow:
          selected
            ? `0 0 6px ${accent}66`
            : hover && !disabled
              ? `0 0 6px ${accent}44`
              : 'none',
        cursor: clickable ? 'pointer' : 'default',
      }}
    >
      <Stack align="center">
        <Stack.Item>
          <Box
            style={{
              width: '22px',
              textAlign: 'center',
              fontSize: '1.05em',
            }}
          >
            {selected ? (
              <Icon name="circle-check" style={{ color: accent }} />
            ) : disabled ? (
              <Icon name="lock" style={{ color: 'rgba(255,255,255,0.35)' }} />
            ) : (
              <Icon name="circle" style={{ color: `${accent}aa` }} />
            )}
          </Box>
        </Stack.Item>
        <Stack.Item grow style={{ minWidth: 0 }}>
          <Box>
            <Box inline bold>
              {perk.name}
            </Box>
            <Box
              inline
              ml={1}
              style={{
                fontSize: '0.72em',
                padding: '1px 6px',
                borderRadius: '8px',
                backgroundColor: `${accent}33`,
                color: accent,
                fontWeight: 'bold',
                verticalAlign: 'middle',
              }}
            >
              {perk.cost} pt{perk.cost === 1 ? '' : 's'}
            </Box>
            {badge && (
              <Box
                inline
                ml={0.5}
                style={{
                  fontSize: '0.7em',
                  padding: '1px 5px',
                  borderRadius: '8px',
                  backgroundColor: 'rgba(255,255,255,0.06)',
                  color: 'rgba(255,255,255,0.7)',
                  verticalAlign: 'middle',
                }}
              >
                <Icon name={badge.icon} mr={0.25} />
                {badge.text}
              </Box>
            )}
          </Box>
          {/* Full description always shown inline — no tooltip wrapper (the
              previous Tooltip wrapping confused the click target). word-wrap
              keeps long descriptions inside the card width. */}
          <Box
            fontSize="0.8em"
            color="label"
            mt={0.25}
            style={{
              whiteSpace: 'normal',
              wordBreak: 'break-word',
              lineHeight: '1.3',
            }}
          >
            {perk.desc}
          </Box>
          {gateHint && (
            <Box fontSize="0.78em" italic style={{ color: BAD }} mt={0.25}>
              <Icon name="triangle-exclamation" mr={0.5} />
              {gateHint}
            </Box>
          )}
        </Stack.Item>
        {/* Right-side action icon — kept icon-only per UX spec. Click handler
            is on the outer Box so any tap on the card toggles the perk. */}
        <Stack.Item>
          <Box
            style={{
              width: '24px',
              height: '24px',
              borderRadius: '50%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              backgroundColor: selected
                ? `${BAD}22`
                : disabled
                  ? 'transparent'
                  : `${accent}33`,
              color: selected ? BAD : disabled ? 'rgba(255,255,255,0.3)' : accent,
              transition: 'all 120ms',
            }}
          >
            <Icon name={selected ? 'xmark' : disabled ? 'lock' : 'plus'} />
          </Box>
        </Stack.Item>
      </Stack>
    </Box>
  );
};
