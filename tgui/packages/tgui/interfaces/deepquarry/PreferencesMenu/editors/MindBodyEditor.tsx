// DQAdd — Mind & Body specialty editor (P7).
//
// Architecture (matches the DM side):
//   Top-level type:  Body | Mind  (two panes, side by side)
//   Per-pane: row of *category* chips (Strength / Vigor / … or
//             Command / Security / …). Each category has its own pool.
//   Active category: pool fill bar + tree(s) for that category. Body
//             categories have a single tree (shown as a perk grid); Mind
//             categories have sub-role trees (rendered as a second
//             chip row that swaps the perk grid).
//   Each tree is a tier-based grid of compact icon cards. Card body =
//   FA icon, name, cost pill. Hover shows full description in a Tooltip.
//   Click toggles take/remove. Connectors between tiers visualise the
//   requires-chain.

import { useEffect, useMemo, useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  AnimatedNumber,
  Box,
  Icon,
  Section,
  Stack,
  Tooltip,
} from 'tgui-core/components';
import type { EditorProps } from './index';

// ─── Types ─────────────────────────────────────────────────────────────────────────

type CategoryType = 'body' | 'mind';
type PerkKind = 'body' | 'mind';

type CategoryMeta = {
  id: string;
  name: string;
  description: string;
  color: string;
  icon: string | null;
  type: CategoryType;
};

type TreeMeta = {
  id: string;
  name: string;
  description: string;
  color: string | null;
  icon: string | null;
  category: string;
  perks: string[];
};

type PerkMeta = {
  name: string;
  desc: string;
  icon: string;
  cost: number;
  perk_kind: PerkKind;
  category: string;
  tree: string;
  requires: string[];
};

type MindBodyData = {
  age: number;
  pools: Record<string, number>;
  spent: Record<string, number>;
  body_perks: string[];
  mind_perks: string[];
};

type MindBodyStatic = {
  categories: Record<string, CategoryMeta>;
  trees: Record<string, TreeMeta>;
  perks: Record<string, PerkMeta>;
  base_per_cat: number;
  max_mind_per_cat: number;
};

const BODY_ACCENT = '#C0392B';
const MIND_ACCENT = '#3498DB';
const BAD = '#E74C3C';

type Act = ReturnType<typeof useBackend>['act'];

const send = (act: Act, action: string, params: Record<string, unknown>) =>
  act('dq_editor_action', { editor: 'mind_body', action, params });

// ─── Root ──────────────────────────────────────────────────────────────────────────

export const MindBodyEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as MindBodyData;
  const s = (staticData ?? {}) as MindBodyStatic;

  const bodyCats = useMemo(
    () =>
      Object.values(s.categories ?? {})
        .filter((c) => c.type === 'body')
        .map((c) => c.id),
    [s.categories],
  );
  const mindCats = useMemo(
    () =>
      Object.values(s.categories ?? {})
        .filter((c) => c.type === 'mind')
        .map((c) => c.id),
    [s.categories],
  );

  // Pick-tally per category, used for tab badges + default-active selection.
  const picksByCat = useMemo(() => {
    const out: Record<string, number> = {};
    for (const path of [...d.body_perks, ...d.mind_perks]) {
      const p = s.perks?.[path];
      if (p) out[p.category] = (out[p.category] ?? 0) + 1;
    }
    return out;
  }, [d.body_perks, d.mind_perks, s.perks]);

  // Active category per pane. Land on an invested category if any, else first.
  const [activeBodyCat, setActiveBodyCat] = useState<string>('');
  const [activeMindCat, setActiveMindCat] = useState<string>('');
  useEffect(() => {
    if (!activeBodyCat && bodyCats.length > 0) {
      const invested = bodyCats.find((id) => (picksByCat[id] ?? 0) > 0);
      setActiveBodyCat(invested ?? bodyCats[0]);
    }
  }, [activeBodyCat, bodyCats, picksByCat]);
  useEffect(() => {
    if (!activeMindCat && mindCats.length > 0) {
      const invested = mindCats.find((id) => (picksByCat[id] ?? 0) > 0);
      setActiveMindCat(invested ?? mindCats[0]);
    }
  }, [activeMindCat, mindCats, picksByCat]);

  if (!s.categories || !s.trees || !s.perks) return null;

  return (
    <Box
      style={{ height: '100%', display: 'flex', flexDirection: 'column' }}
    >
      <TopHeader age={d.age} />
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
          <SidePane
            paneLabel="Body"
            paneIcon="dumbbell"
            paneAccent={BODY_ACCENT}
            categoryIds={bodyCats}
            activeCategoryId={activeBodyCat}
            setActiveCategoryId={setActiveBodyCat}
            data={d}
            staticData={s}
            picksByCat={picksByCat}
            selectedPaths={d.body_perks}
            act={act}
          />
        </Box>
        <Box ml={0.5} style={{ flex: 1, minWidth: 0, display: 'flex' }}>
          <SidePane
            paneLabel="Mind"
            paneIcon="brain"
            paneAccent={MIND_ACCENT}
            categoryIds={mindCats}
            activeCategoryId={activeMindCat}
            setActiveCategoryId={setActiveMindCat}
            data={d}
            staticData={s}
            picksByCat={picksByCat}
            selectedPaths={d.mind_perks}
            act={act}
          />
        </Box>
      </Box>
    </Box>
  );
};

// ─── Top header (age + grand totals) ──────────────────────────────────────────────

const TopHeader = ({ age }: { age: number }) => (
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
        <AgeBadge age={age} />
      </Stack.Item>
      <Stack.Item grow>
        <Box ml={1} fontSize="0.85em" color="label">
          Each <Box inline bold style={{ color: BODY_ACCENT }}>Body</Box>{' '}
          and <Box inline bold style={{ color: MIND_ACCENT }}>Mind</Box>{' '}
          category has its own point pool. Younger characters get more Body
          per category; older characters get more Mind. Spending in one
          category does not draw from another.
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

// ─── Side pane (Body or Mind) ─────────────────────────────────────────────────────

const SidePane = ({
  paneLabel,
  paneIcon,
  paneAccent,
  categoryIds,
  activeCategoryId,
  setActiveCategoryId,
  data: d,
  staticData: s,
  picksByCat,
  selectedPaths,
  act,
}: {
  paneLabel: string;
  paneIcon: string;
  paneAccent: string;
  categoryIds: string[];
  activeCategoryId: string;
  setActiveCategoryId: (id: string) => void;
  data: MindBodyData;
  staticData: MindBodyStatic;
  picksByCat: Record<string, number>;
  selectedPaths: string[];
  act: Act;
}) => {
  const activeCat = s.categories[activeCategoryId];
  return (
    <Section
      fill
      scrollable
      style={{ flex: 1, display: 'flex' }}
      title={<PaneTitle icon={paneIcon} color={paneAccent} label={paneLabel} />}
    >
      <CategoryTabRow
        categoryIds={categoryIds}
        activeCategoryId={activeCategoryId}
        setActiveCategoryId={setActiveCategoryId}
        categories={s.categories}
        pools={d.pools}
        spent={d.spent}
        picksByCat={picksByCat}
      />
      {activeCat && (
        <CategoryPane
          category={activeCat}
          staticData={s}
          pool={d.pools[activeCat.id] ?? 0}
          spent={d.spent[activeCat.id] ?? 0}
          selectedPaths={selectedPaths}
          act={act}
        />
      )}
    </Section>
  );
};

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

// ─── Category tab row ─────────────────────────────────────────────────────────────

const CategoryTabRow = ({
  categoryIds,
  activeCategoryId,
  setActiveCategoryId,
  categories,
  pools,
  spent,
  picksByCat,
}: {
  categoryIds: string[];
  activeCategoryId: string;
  setActiveCategoryId: (id: string) => void;
  categories: Record<string, CategoryMeta>;
  pools: Record<string, number>;
  spent: Record<string, number>;
  picksByCat: Record<string, number>;
}) => (
  <Stack wrap mb={1}>
    {categoryIds.map((id) => {
      const cat = categories[id];
      if (!cat) return null;
      return (
        <Stack.Item key={id}>
          <CategoryChip
            cat={cat}
            isActive={id === activeCategoryId}
            pool={pools[id] ?? 0}
            spent={spent[id] ?? 0}
            picks={picksByCat[id] ?? 0}
            onClick={() => setActiveCategoryId(id)}
          />
        </Stack.Item>
      );
    })}
  </Stack>
);

const CategoryChip = ({
  cat,
  isActive,
  pool,
  spent,
  picks,
  onClick,
}: {
  cat: CategoryMeta;
  isActive: boolean;
  pool: number;
  spent: number;
  picks: number;
  onClick: () => void;
}) => {
  const [hover, setHover] = useState(false);
  const remaining = pool - spent;
  const bg = isActive
    ? cat.color
    : hover
      ? `${cat.color}33`
      : 'rgba(255,255,255,0.05)';
  const fg = isActive ? '#fff' : cat.color;
  const border = isActive
    ? cat.color
    : hover
      ? cat.color
      : 'rgba(255,255,255,0.12)';
  return (
    <Tooltip
      content={
        <Box style={{ maxWidth: '260px' }}>
          <Box bold style={{ color: cat.color }}>
            {cat.name}
          </Box>
          <Box fontSize="0.85em">{cat.description}</Box>
          <Box fontSize="0.85em" color="label" mt={0.5}>
            Pool: {spent} / {pool} ({remaining} left)
          </Box>
        </Box>
      }
    >
      <Box
        mr={0.5}
        mb={0.5}
        onClick={onClick}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
        style={{
          cursor: 'pointer',
          padding: '4px 10px',
          borderRadius: '14px',
          backgroundColor: bg,
          border: `1px solid ${border}`,
          color: fg,
          fontWeight: isActive || picks > 0 ? 'bold' : 'normal',
          fontSize: '0.85em',
          transition: 'all 120ms',
          display: 'inline-flex',
          alignItems: 'center',
          gap: '6px',
          boxShadow: isActive ? `0 0 6px ${cat.color}66` : 'none',
        }}
      >
        {cat.icon && <Icon name={cat.icon} />}
        {cat.name}
        <Box
          style={{
            backgroundColor: isActive
              ? 'rgba(255,255,255,0.25)'
              : `${cat.color}44`,
            borderRadius: '8px',
            padding: '0 6px',
            fontSize: '0.85em',
            fontWeight: 'bold',
          }}
        >
          {spent}/{pool}
        </Box>
      </Box>
    </Tooltip>
  );
};

// ─── Category pane (active tab content) ───────────────────────────────────────────

const CategoryPane = ({
  category,
  staticData: s,
  pool,
  spent,
  selectedPaths,
  act,
}: {
  category: CategoryMeta;
  staticData: MindBodyStatic;
  pool: number;
  spent: number;
  selectedPaths: string[];
  act: Act;
}) => {
  // Trees in this category. Body cats have 1 tree; Mind cats have multiple
  // sub-role trees.
  const treesInCat = useMemo(
    () =>
      Object.values(s.trees).filter((t) => t.category === category.id),
    [s.trees, category.id],
  );

  // Active sub-tree (relevant for Mind only — Body cats have 1 tree).
  const [activeTreeId, setActiveTreeId] = useState<string>('');
  useEffect(() => {
    if (treesInCat.length === 0) return;
    const valid = treesInCat.some((t) => t.id === activeTreeId);
    if (!valid) setActiveTreeId(treesInCat[0].id);
  }, [treesInCat, activeTreeId]);

  const remaining = pool - spent;
  const activeTree = treesInCat.find((t) => t.id === activeTreeId);

  return (
    <Box>
      <PoolFillBar
        spent={spent}
        pool={pool}
        accent={category.color}
        label={`${category.name} pool`}
      />

      {/* Only render the sub-tree tab strip when there's more than one — Body
          categories collapse the strip to save vertical space. */}
      {treesInCat.length > 1 && (
        <Stack wrap mt={0.5}>
          {treesInCat.map((t) => (
            <Stack.Item key={t.id}>
              <SubTreeChip
                tree={t}
                accent={category.color}
                isActive={t.id === activeTreeId}
                pickedHere={
                  t.perks.filter((p) => selectedPaths.includes(p)).length
                }
                onClick={() => setActiveTreeId(t.id)}
              />
            </Stack.Item>
          ))}
        </Stack>
      )}

      {activeTree && (
        <Box mt={1}>
          <PerkTree
            tree={activeTree}
            categoryColor={category.color}
            perks={s.perks}
            selectedPaths={selectedPaths}
            remaining={remaining}
            act={act}
          />
        </Box>
      )}
    </Box>
  );
};

// ─── Pool fill bar (per-category) ─────────────────────────────────────────────────

const PoolFillBar = ({
  spent,
  pool,
  accent,
  label,
}: {
  spent: number;
  pool: number;
  accent: string;
  label: string;
}) => {
  const safePool = Math.max(pool, 1);
  const fillPct = Math.min(100, (spent / safePool) * 100);
  const remaining = Math.max(0, pool - spent);
  return (
    <Box>
      <Stack align="center" mb={0.25}>
        <Stack.Item grow>
          <Box fontSize="0.78em" color="label">
            {label}
          </Box>
        </Stack.Item>
        <Stack.Item>
          <Box fontSize="0.78em">
            <Box inline bold style={{ color: accent }}>
              {spent}
            </Box>
            <Box inline color="label">
              {' '}
              / {pool} ·{' '}
            </Box>
            <Box inline bold style={{ color: '#fff' }}>
              <AnimatedNumber value={remaining} />
            </Box>
            <Box inline color="label">
              {' '}
              free
            </Box>
          </Box>
        </Stack.Item>
      </Stack>
      <Box
        style={{
          display: 'flex',
          height: '8px',
          borderRadius: '4px',
          overflow: 'hidden',
          backgroundColor: 'rgba(0,0,0,0.4)',
          border: '1px solid rgba(255,255,255,0.08)',
          boxShadow: 'inset 0 0 4px rgba(0,0,0,0.4)',
        }}
      >
        <Box
          style={{
            width: `${fillPct}%`,
            background: `linear-gradient(180deg, ${accent}, ${accent}cc)`,
            transition: 'width 200ms',
            boxShadow: `0 0 4px ${accent}`,
          }}
        />
      </Box>
    </Box>
  );
};

// ─── Sub-tree chip (Mind sub-roles) ───────────────────────────────────────────────

const SubTreeChip = ({
  tree,
  accent,
  isActive,
  pickedHere,
  onClick,
}: {
  tree: TreeMeta;
  accent: string;
  isActive: boolean;
  pickedHere: number;
  onClick: () => void;
}) => {
  const [hover, setHover] = useState(false);
  return (
    <Box
      mr={0.25}
      mb={0.25}
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        cursor: 'pointer',
        padding: '2px 8px',
        borderRadius: '10px',
        backgroundColor: isActive
          ? `${accent}cc`
          : hover
            ? `${accent}22`
            : 'rgba(255,255,255,0.04)',
        border: `1px solid ${isActive || hover ? accent : 'rgba(255,255,255,0.1)'}`,
        color: isActive ? '#fff' : accent,
        fontWeight: isActive || pickedHere > 0 ? 'bold' : 'normal',
        fontSize: '0.78em',
        transition: 'all 120ms',
        display: 'inline-flex',
        alignItems: 'center',
        gap: '5px',
      }}
    >
      {tree.icon && <Icon name={tree.icon} />}
      {tree.name}
      {pickedHere > 0 && (
        <Box
          style={{
            backgroundColor: isActive
              ? 'rgba(255,255,255,0.25)'
              : `${accent}44`,
            borderRadius: '7px',
            padding: '0 5px',
            fontSize: '0.85em',
          }}
        >
          {pickedHere}
        </Box>
      )}
    </Box>
  );
};

// ─── Perk tree (skill-tree layout with SVG connectors) ────────────────────────────
//
// Layout algorithm:
//   1. Compute tier (max-depth of the requires chain) for every perk.
//   2. Tier 0 perks sit at the top, spread evenly along x.
//   3. Each subsequent tier's perks are positioned near their primary parent.
//      Siblings sharing a parent fan out around that parent's x slot.
//   4. After all positions are assigned, normalize so the leftmost perk sits at
//      x=0 and compute the total grid width.
//   5. Connections (parent → child) are rendered as curved SVG paths underneath
//      the perk nodes, colored with the tree accent so the dependency reads at
//      a glance.
//
// Sizing: NODE_W × NODE_H is the card footprint; ROW_GAP and COL_GAP are the
// gaps between tiers and siblings respectively. Tuned to be comfortably tappable
// without making four-tier trees overflow the pane.

const NODE_W = 92;
const NODE_H = 84;
const COL_GAP = 16;
const ROW_GAP = 36;

type LayoutNode = {
  path: string;
  meta: PerkMeta;
  tier: number;
  x: number;
  y: number;
};

type Connection = {
  fromPath: string;
  toPath: string;
  x1: number;
  y1: number;
  x2: number;
  y2: number;
};

const computeTreeLayout = (
  treePerks: string[],
  perks: Record<string, PerkMeta>,
) => {
  // 1. Reduce to just the perks that live in this tree AND have meta entries.
  const byPath: Record<string, PerkMeta> = {};
  for (const p of treePerks) {
    const meta = perks[p];
    if (meta) byPath[p] = meta;
  }

  const allPaths = Object.keys(byPath);

  // 2. Tier (depth in the requires DAG).
  const tierCache: Record<string, number> = {};
  const tierOf = (path: string, visiting = new Set<string>()): number => {
    if (path in tierCache) return tierCache[path];
    const meta = byPath[path];
    if (!meta || meta.requires.length === 0) {
      tierCache[path] = 0;
      return 0;
    }
    if (visiting.has(path)) return 0; // cycle guard
    visiting.add(path);
    const t =
      1 +
      Math.max(
        ...meta.requires.map((r) =>
          byPath[r] ? tierOf(r, visiting) : -1,
        ),
      );
    visiting.delete(path);
    tierCache[path] = t;
    return t;
  };

  for (const p of allPaths) tierOf(p);

  // 3. Group by tier and sort tier-0 by name for stability.
  const tiers: string[][] = [];
  for (const p of allPaths) {
    const t = tierCache[p];
    if (!tiers[t]) tiers[t] = [];
    tiers[t].push(p);
  }
  for (let t = 0; t < tiers.length; t++) {
    if (!tiers[t]) tiers[t] = [];
  }
  tiers[0]?.sort((a, b) => byPath[a].name.localeCompare(byPath[b].name));

  // 4. Assign x positions. Tier 0 spaced evenly; later tiers cluster around
  //    their first parent's slot.
  const xByPath: Record<string, number> = {};
  // Tier 0 → evenly spaced columns.
  tiers[0]?.forEach((path, idx) => {
    xByPath[path] = idx * (NODE_W + COL_GAP);
  });
  for (let t = 1; t < tiers.length; t++) {
    const tierList = tiers[t];
    if (!tierList) continue;
    // Group by primary parent so siblings sharing a parent fan out together.
    const byParent: Record<string, string[]> = {};
    for (const path of tierList) {
      const primary = byPath[path].requires[0] ?? '__rootless__';
      if (!byParent[primary]) byParent[primary] = [];
      byParent[primary].push(path);
    }
    // For each parent group, position children spread around parent's x.
    // Sort the parents by their x so iteration order matches visual order
    // (left → right), which prevents overlapping when two adjacent parents
    // have many children.
    const parentEntries = Object.entries(byParent).sort(([a], [b]) => {
      const ax = xByPath[a] ?? 0;
      const bx = xByPath[b] ?? 0;
      return ax - bx;
    });
    let runningX = 0;
    for (const [parent, children] of parentEntries) {
      const parentX = xByPath[parent] ?? 0;
      const groupWidth =
        children.length * NODE_W + (children.length - 1) * COL_GAP;
      // Center this group on the parent's x, but never overlap the previous
      // group (running cursor).
      const startX = Math.max(runningX, parentX - groupWidth / 2);
      children.forEach((path, idx) => {
        xByPath[path] = startX + idx * (NODE_W + COL_GAP);
      });
      runningX = startX + groupWidth + COL_GAP;
    }
  }

  // 5. Normalize x so minimum is 0; compute total grid extents.
  const xs = Object.values(xByPath);
  const minX = xs.length > 0 ? Math.min(...xs) : 0;
  for (const p of allPaths) xByPath[p] -= minX;
  const maxX = Math.max(0, ...Object.values(xByPath));

  // 6. Build node + connection arrays.
  const nodes: LayoutNode[] = allPaths.map((path) => ({
    path,
    meta: byPath[path],
    tier: tierCache[path],
    x: xByPath[path],
    y: tierCache[path] * (NODE_H + ROW_GAP),
  }));
  const connections: Connection[] = [];
  for (const path of allPaths) {
    const meta = byPath[path];
    for (const req of meta.requires) {
      if (!(req in xByPath)) continue;
      connections.push({
        fromPath: req,
        toPath: path,
        x1: xByPath[req] + NODE_W / 2,
        y1: tierCache[req] * (NODE_H + ROW_GAP) + NODE_H,
        x2: xByPath[path] + NODE_W / 2,
        y2: tierCache[path] * (NODE_H + ROW_GAP),
      });
    }
  }

  const totalWidth = maxX + NODE_W;
  const totalHeight =
    (tiers.length > 0 ? tiers.length - 1 : 0) * (NODE_H + ROW_GAP) + NODE_H;
  return { nodes, connections, totalWidth, totalHeight };
};

const PerkTree = ({
  tree,
  categoryColor,
  perks,
  selectedPaths,
  remaining,
  act,
}: {
  tree: TreeMeta;
  categoryColor: string;
  perks: Record<string, PerkMeta>;
  selectedPaths: string[];
  remaining: number;
  act: Act;
}) => {
  const accent = tree.color ?? categoryColor;
  const { nodes, connections, totalWidth, totalHeight } = useMemo(
    () => computeTreeLayout(tree.perks, perks),
    [tree.perks, perks],
  );

  return (
    // Outer scroll container so wide trees pan horizontally inside the pane
    // instead of overflowing the page.
    <Box
      style={{
        overflowX: 'auto',
        overflowY: 'hidden',
        paddingBottom: '6px',
      }}
    >
      <Box
        style={{
          position: 'relative',
          width: `${totalWidth}px`,
          minWidth: '100%',
          height: `${totalHeight}px`,
        }}
      >
        {/* SVG layer for parent → child connectors. pointer-events: none so the
            lines never intercept clicks meant for a node sitting on top. */}
        <svg
          width={totalWidth}
          height={totalHeight}
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            pointerEvents: 'none',
          }}
        >
          {connections.map((c) => {
            const parentSelected = selectedPaths.includes(c.fromPath);
            const childSelected = selectedPaths.includes(c.toPath);
            const bothSelected = parentSelected && childSelected;
            // Smooth cubic-bezier from parent's bottom to child's top so the
            // path obviously originates from the parent rather than a generic
            // mid-tier divider.
            const midY = (c.y1 + c.y2) / 2;
            const d = `M ${c.x1} ${c.y1} C ${c.x1} ${midY}, ${c.x2} ${midY}, ${c.x2} ${c.y2}`;
            return (
              <path
                key={`${c.fromPath}-${c.toPath}`}
                d={d}
                stroke={accent}
                strokeWidth={bothSelected ? 2.5 : 1.5}
                strokeOpacity={
                  bothSelected ? 0.85 : parentSelected ? 0.65 : 0.35
                }
                strokeDasharray={bothSelected ? undefined : '5 3'}
                fill="none"
              />
            );
          })}
        </svg>

        {/* Perk nodes — absolutely positioned. */}
        {nodes.map(({ path, meta, x, y }) => {
          const selected = selectedPaths.includes(path);
          const requiresOk = meta.requires.every((r) =>
            selectedPaths.includes(r),
          );
          const affordable = selected || remaining >= meta.cost;
          const disabled = !selected && (!requiresOk || !affordable);
          return (
            <Box
              key={path}
              style={{
                position: 'absolute',
                left: `${x}px`,
                top: `${y}px`,
                width: `${NODE_W}px`,
                height: `${NODE_H}px`,
              }}
            >
              <PerkNode
                perk={meta}
                accent={accent}
                selected={selected}
                disabled={disabled}
                gateHint={
                  !selected && !requiresOk
                    ? `Requires ${meta.requires
                        .map((r) => perks[r]?.name ?? r)
                        .join(', ')}`
                    : !selected && !affordable
                      ? 'Not enough points in this category'
                      : null
                }
                onClick={() =>
                  send(act, selected ? 'remove_perk' : 'add_perk', {
                    perk_path: path,
                  })
                }
              />
            </Box>
          );
        })}
      </Box>
    </Box>
  );
};

// ─── Perk node (compact icon card) ────────────────────────────────────────────────

const PerkNode = ({
  perk,
  accent,
  selected,
  disabled,
  gateHint,
  onClick,
}: {
  perk: PerkMeta;
  accent: string;
  selected: boolean;
  disabled: boolean;
  gateHint: string | null;
  onClick: () => void;
}) => {
  const [hover, setHover] = useState(false);
  const clickable = selected || !disabled;
  const bg = selected
    ? `linear-gradient(180deg, ${accent}44, ${accent}11)`
    : disabled
      ? 'rgba(255,255,255,0.02)'
      : hover
        ? `${accent}22`
        : 'rgba(255,255,255,0.04)';
  const border = selected
    ? `1px solid ${accent}`
    : disabled
      ? '1px solid rgba(255,255,255,0.06)'
      : hover
        ? `1px solid ${accent}`
        : `1px solid ${accent}55`;
  return (
    <Tooltip
      content={
        <Box style={{ maxWidth: '300px' }}>
          <Box bold style={{ color: accent }} mb={0.25}>
            <Icon name={perk.icon} mr={0.5} />
            {perk.name}
            <Box
              inline
              ml={1}
              style={{
                fontSize: '0.78em',
                padding: '1px 6px',
                borderRadius: '8px',
                backgroundColor: `${accent}44`,
                color: '#fff',
                fontWeight: 'bold',
                verticalAlign: 'middle',
              }}
            >
              {perk.cost} pt{perk.cost === 1 ? '' : 's'}
            </Box>
          </Box>
          <Box fontSize="0.9em">{perk.desc}</Box>
          {gateHint && (
            <Box fontSize="0.85em" italic style={{ color: BAD }} mt={0.5}>
              <Icon name="triangle-exclamation" mr={0.5} />
              {gateHint}
            </Box>
          )}
        </Box>
      }
    >
      <Box
        onClick={clickable ? onClick : undefined}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
        style={{
          cursor: clickable ? 'pointer' : 'default',
          width: '100%',
          height: '100%',
          padding: '5px 4px',
          borderRadius: '8px',
          background: bg,
          border,
          opacity: disabled ? 0.55 : 1,
          transition: 'all 120ms',
          boxShadow: selected
            ? `0 0 8px ${accent}88`
            : hover && !disabled
              ? `0 0 6px ${accent}55`
              : 'none',
          textAlign: 'center',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        <Box style={{ position: 'relative', width: '100%', height: '40px' }}>
          <Box
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              height: '40px',
            }}
          >
            <Icon
              name={perk.icon}
              size={2.0}
              style={{
                color: selected
                  ? '#fff'
                  : disabled
                    ? 'rgba(255,255,255,0.3)'
                    : accent,
                filter: selected
                  ? `drop-shadow(0 0 4px ${accent})`
                  : undefined,
              }}
            />
          </Box>
          {selected && (
            <Box
              style={{
                position: 'absolute',
                top: -2,
                right: -2,
                background: accent,
                borderRadius: '50%',
                width: '16px',
                height: '16px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '0.7em',
                color: '#fff',
                boxShadow: '0 0 4px rgba(0,0,0,0.7)',
              }}
            >
              <Icon name="check" />
            </Box>
          )}
          {!selected && disabled && (
            <Box
              style={{
                position: 'absolute',
                top: -2,
                right: -2,
                background: 'rgba(0,0,0,0.7)',
                borderRadius: '50%',
                width: '16px',
                height: '16px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '0.7em',
                color: 'rgba(255,255,255,0.7)',
              }}
            >
              <Icon name="lock" />
            </Box>
          )}
        </Box>
        <Box
          fontSize="0.74em"
          style={{
            color: selected ? '#fff' : 'rgba(255,255,255,0.92)',
            fontWeight: selected ? 'bold' : 'normal',
            lineHeight: '1.1',
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            width: '100%',
          }}
        >
          {perk.name}
        </Box>
        <Box
          fontSize="0.68em"
          style={{
            color: accent,
            fontWeight: 'bold',
            background: `${accent}22`,
            padding: '0 6px',
            borderRadius: '6px',
          }}
        >
          {perk.cost}
        </Box>
      </Box>
    </Tooltip>
  );
};
