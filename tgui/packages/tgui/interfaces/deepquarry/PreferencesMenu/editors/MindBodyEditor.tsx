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

type SideKind = 'body' | 'mind';

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

  // Top-level Body vs Mind toggle. Only one side renders at a time so the tree
  // can use the entire left-pane width (~700px) without horizontal scrolling.
  const [activeKind, setActiveKind] = useState<SideKind>('body');

  // Active category per side. Land on an invested category if any, else first.
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
      <TopHeader
        age={d.age}
        activeKind={activeKind}
        setActiveKind={setActiveKind}
      />
      <Box
        mt={0.5}
        style={{ flex: 1, minHeight: 0, display: 'flex' }}
      >
        {activeKind === 'body' ? (
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
        ) : (
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
        )}
      </Box>
    </Box>
  );
};

// ─── Top header (age + side toggle) ───────────────────────────────────────────────

const TopHeader = ({
  age,
  activeKind,
  setActiveKind,
}: {
  age: number;
  activeKind: SideKind;
  setActiveKind: (k: SideKind) => void;
}) => (
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
        <Box ml={1}>
          <SideToggle activeKind={activeKind} setActiveKind={setActiveKind} />
        </Box>
      </Stack.Item>
    </Stack>
  </Box>
);

const SideToggle = ({
  activeKind,
  setActiveKind,
}: {
  activeKind: SideKind;
  setActiveKind: (k: SideKind) => void;
}) => (
  <Stack>
    <Stack.Item grow>
      <SidePill
        kind="body"
        label="Body"
        icon="dumbbell"
        accent={BODY_ACCENT}
        active={activeKind === 'body'}
        onClick={() => setActiveKind('body')}
      />
    </Stack.Item>
    <Stack.Item grow>
      <SidePill
        kind="mind"
        label="Mind"
        icon="brain"
        accent={MIND_ACCENT}
        active={activeKind === 'mind'}
        onClick={() => setActiveKind('mind')}
      />
    </Stack.Item>
  </Stack>
);

const SidePill = ({
  label,
  icon,
  accent,
  active,
  onClick,
}: {
  kind: SideKind;
  label: string;
  icon: string;
  accent: string;
  active: boolean;
  onClick: () => void;
}) => {
  const [hover, setHover] = useState(false);
  return (
    <Box
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        cursor: 'pointer',
        padding: '8px 16px',
        borderRadius: '8px',
        backgroundColor: active
          ? accent
          : hover
            ? `${accent}33`
            : 'rgba(255,255,255,0.05)',
        border: `1px solid ${active || hover ? accent : 'rgba(255,255,255,0.12)'}`,
        color: active ? '#fff' : accent,
        fontWeight: 'bold',
        fontSize: '1em',
        textAlign: 'center',
        letterSpacing: '0.05em',
        transition: 'all 120ms',
        boxShadow: active ? `0 0 8px ${accent}88` : 'none',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: '8px',
      }}
    >
      <Icon name={icon} size={1.2} />
      {label}
    </Box>
  );
};

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

// ─── Perk tree (subtree-packed layout with straight + right-angle connectors) ─────
//
// Layout strategy: a tree of perks is laid out as a row of "subtrees". Each subtree
// is rooted at a tier-0 perk and contains all of its descendants. Subtrees that
// don't fit in the available width wrap to a new row so the whole tree fits without
// horizontal scrolling. Inside a subtree:
//   - A perk with one child puts that child directly below it (straight vertical
//     line, no bezier).
//   - A perk with N children spreads them horizontally below it; the subtree's
//     width grows accordingly.
//   - The subtree's total width = max(1, sum(width of each child subtree)).
//
// Cross-subtree dependencies (a perk that requires perks from multiple subtrees)
// route via a right-angle path: down from the parent's bottom edge, across to the
// child's column, then down into the child's top edge.

const NODE_W = 78;
const NODE_H = 68;
const COL_GAP = 8;
const ROW_GAP = 22;
const SUBTREE_ROW_GAP = 16;
// Single-pane layout sits in the left ~2/3 of the 1100×760 window. The Section
// frame and side padding leave roughly 680px usable; cap at 660 so the rightmost
// subtree doesn't kiss the scrollbar gutter.
const PANE_WIDTH = 660;

type LayoutNode = {
  path: string;
  meta: PerkMeta;
  tier: number;
  x: number;
  y: number;
  // The subtree this perk belongs to (root path). Used so the connector layer
  // can distinguish intra-subtree links (straight) from cross-subtree links
  // (right-angle paths).
  rootPath: string;
};

type Connection = {
  fromPath: string;
  toPath: string;
  /// True when both endpoints share the same root (same column block) — render
  /// as a straight vertical line.
  intraSubtree: boolean;
};

/// Recursively compute the column width a subtree occupies. Memoised by path.
const subtreeWidth = (
  path: string,
  childrenOf: Record<string, string[]>,
  cache: Record<string, number>,
): number => {
  if (path in cache) return cache[path];
  const children = childrenOf[path] ?? [];
  if (children.length === 0) {
    cache[path] = 1;
    return 1;
  }
  let total = 0;
  for (const child of children) total += subtreeWidth(child, childrenOf, cache);
  cache[path] = Math.max(1, total);
  return cache[path];
};

const computeTreeLayout = (
  treePerks: string[],
  perks: Record<string, PerkMeta>,
) => {
  // 1. Reduce to just this tree's perks.
  const byPath: Record<string, PerkMeta> = {};
  for (const p of treePerks) {
    const meta = perks[p];
    if (meta) byPath[p] = meta;
  }
  const allPaths = Object.keys(byPath);

  // 2. Compute tier (max-depth of the requires DAG) — using *all* parents, not
  //    just the primary. This guarantees a child is always placed below every
  //    one of its parents, so connector lines only ever go downward.
  const tierCache: Record<string, number> = {};
  const tierOf = (path: string, visiting = new Set<string>()): number => {
    if (path in tierCache) return tierCache[path];
    const meta = byPath[path];
    if (!meta || meta.requires.length === 0) {
      tierCache[path] = 0;
      return 0;
    }
    if (visiting.has(path)) return 0;
    visiting.add(path);
    let maxParent = -1;
    for (const req of meta.requires) {
      if (req in byPath) {
        maxParent = Math.max(maxParent, tierOf(req, visiting));
      }
    }
    visiting.delete(path);
    const t = 1 + (maxParent >= 0 ? maxParent : 0);
    tierCache[path] = t;
    return t;
  };
  for (const p of allPaths) tierOf(p);

  // 3. Choose the *primary* parent for subtree routing. Picking the parent with
  //    the highest tier means the child gets routed into the deepest subtree —
  //    the one whose chain it logically extends. That subtree is also the one
  //    the orthogonal connector layout will already direct lines toward.
  const primaryParent: Record<string, string | null> = {};
  for (const path of allPaths) {
    const reqs = byPath[path].requires;
    let chosen: string | null = null;
    let chosenTier = -1;
    for (const req of reqs) {
      if (req in byPath && tierCache[req] > chosenTier) {
        chosen = req;
        chosenTier = tierCache[req];
      }
    }
    primaryParent[path] = chosen;
  }
  const childrenOf: Record<string, string[]> = {};
  for (const path of allPaths) {
    const parent = primaryParent[path];
    if (parent) {
      if (!childrenOf[parent]) childrenOf[parent] = [];
      childrenOf[parent].push(path);
    }
  }
  for (const parent in childrenOf) {
    childrenOf[parent].sort((a, b) =>
      byPath[a].name.localeCompare(byPath[b].name),
    );
  }

  // 4. Identify roots (tier 0) and compute each subtree's column width.
  const roots = allPaths.filter((p) => primaryParent[p] === null);
  roots.sort((a, b) => byPath[a].name.localeCompare(byPath[b].name));
  const widthCache: Record<string, number> = {};
  for (const r of roots) subtreeWidth(r, childrenOf, widthCache);

  // 5. Position subtree roots into rows that fit PANE_WIDTH. Each subtree
  //    occupies (width × (NODE_W + COL_GAP)) horizontal space; subtrees are
  //    separated by SUBTREE_GAP.
  type Row = { roots: string[]; totalCols: number; maxTier: number };
  const rows: Row[] = [];
  let cur: Row = { roots: [], totalCols: 0, maxTier: 0 };
  const colsThatFit = Math.floor(
    (PANE_WIDTH + COL_GAP) / (NODE_W + COL_GAP),
  );
  for (const r of roots) {
    const w = widthCache[r];
    if (cur.totalCols + w > colsThatFit && cur.roots.length > 0) {
      rows.push(cur);
      cur = { roots: [], totalCols: 0, maxTier: 0 };
    }
    cur.roots.push(r);
    cur.totalCols += w;
    cur.maxTier = Math.max(
      cur.maxTier,
      ...allPathsInSubtree(r, childrenOf).map((p) => tierCache[p]),
    );
  }
  if (cur.roots.length > 0) rows.push(cur);

  // 6. Assign (x, y) positions. For each row: walk subtrees left to right,
  //    assigning columns to each leaf via a depth-first pre-order. Internal
  //    nodes center over their children's column span.
  const xByPath: Record<string, number> = {};
  const yByPath: Record<string, number> = {};
  const rootOf: Record<string, string> = {};
  let rowYOffset = 0;

  const assignSubtreePositions = (
    path: string,
    rowYStart: number,
    leftCol: number,
    rootForPath: string,
  ): number => {
    rootOf[path] = rootForPath;
    const children = childrenOf[path] ?? [];
    if (children.length === 0) {
      xByPath[path] = leftCol * (NODE_W + COL_GAP);
      yByPath[path] = rowYStart + tierCache[path] * (NODE_H + ROW_GAP);
      return leftCol + 1;
    }
    let cursor = leftCol;
    const childCols: number[] = [];
    for (const child of children) {
      const start = cursor;
      cursor = assignSubtreePositions(child, rowYStart, cursor, rootForPath);
      childCols.push((start + cursor - 1) / 2);
    }
    // Center this node over the span of its children's columns.
    const centerCol = (childCols[0] + childCols[childCols.length - 1]) / 2;
    xByPath[path] = centerCol * (NODE_W + COL_GAP);
    yByPath[path] = rowYStart + tierCache[path] * (NODE_H + ROW_GAP);
    return cursor;
  };

  for (const row of rows) {
    let colCursor = 0;
    const rowHeight = (row.maxTier + 1) * (NODE_H + ROW_GAP) - ROW_GAP;
    for (const r of row.roots) {
      assignSubtreePositions(r, rowYOffset, colCursor, r);
      colCursor += widthCache[r];
    }
    rowYOffset += rowHeight + SUBTREE_ROW_GAP;
  }

  const nodes: LayoutNode[] = allPaths.map((path) => ({
    path,
    meta: byPath[path],
    tier: tierCache[path],
    x: xByPath[path],
    y: yByPath[path],
    rootPath: rootOf[path] ?? path,
  }));

  // 7. Build connections. Primary-parent links are intra-subtree (straight); any
  //    additional requires (multi-parent perks) cross subtrees.
  const connections: Connection[] = [];
  for (const path of allPaths) {
    const meta = byPath[path];
    for (let i = 0; i < meta.requires.length; i++) {
      const req = meta.requires[i];
      if (!(req in byPath)) continue;
      connections.push({
        fromPath: req,
        toPath: path,
        intraSubtree: rootOf[req] === rootOf[path],
      });
    }
  }

  const totalWidth = Math.max(
    PANE_WIDTH,
    ...Object.values(xByPath).map((x) => x + NODE_W),
  );
  const totalHeight = rowYOffset - SUBTREE_ROW_GAP;
  return { nodes, connections, totalWidth, totalHeight, xByPath, yByPath };
};

const allPathsInSubtree = (
  root: string,
  childrenOf: Record<string, string[]>,
): string[] => {
  const out = [root];
  for (const c of childrenOf[root] ?? []) out.push(...allPathsInSubtree(c, childrenOf));
  return out;
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
  const { nodes, connections, totalWidth, totalHeight, xByPath, yByPath } =
    useMemo(() => computeTreeLayout(tree.perks, perks), [tree.perks, perks]);

  return (
    <Box
      style={{
        position: 'relative',
        width: `${totalWidth}px`,
        minWidth: '100%',
        height: `${totalHeight}px`,
        maxWidth: '100%',
      }}
    >
      {/* Connector layer underneath the nodes. pointer-events: none so clicks pass
          through to the perks. */}
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
          const x1 = (xByPath[c.fromPath] ?? 0) + NODE_W / 2;
          const y1 = (yByPath[c.fromPath] ?? 0) + NODE_H;
          const x2 = (xByPath[c.toPath] ?? 0) + NODE_W / 2;
          const y2 = yByPath[c.toPath] ?? 0;
          const parentSelected = selectedPaths.includes(c.fromPath);
          const childSelected = selectedPaths.includes(c.toPath);
          const bothSelected = parentSelected && childSelected;
          let d: string;
          if (c.intraSubtree && Math.abs(x1 - x2) < 1) {
            // Straight vertical line — child is exactly under parent.
            d = `M ${x1} ${y1} L ${x2} ${y2}`;
          } else {
            // Right-angle path: down halfway, across to child's column, then
            // down again. Clean orthogonal routing for cross-column links.
            const midY = (y1 + y2) / 2;
            d = `M ${x1} ${y1} L ${x1} ${midY} L ${x2} ${midY} L ${x2} ${y2}`;
          }
          return (
            <path
              key={`${c.fromPath}-${c.toPath}`}
              d={d}
              stroke={accent}
              strokeWidth={bothSelected ? 2.5 : 1.5}
              strokeOpacity={
                bothSelected ? 0.9 : parentSelected ? 0.65 : 0.35
              }
              strokeDasharray={bothSelected ? undefined : '4 3'}
              fill="none"
              strokeLinejoin="round"
            />
          );
        })}
      </svg>

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
          padding: '4px 3px',
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
        <Box style={{ position: 'relative', width: '100%', height: '32px' }}>
          <Box
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              height: '32px',
            }}
          >
            <Icon
              name={perk.icon}
              size={1.6}
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
            lineHeight: '1.05',
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            width: '100%',
            fontSize: '0.68em',
          }}
        >
          {perk.name}
        </Box>
        <Box
          fontSize="0.62em"
          style={{
            color: accent,
            fontWeight: 'bold',
            background: `${accent}22`,
            padding: '0 5px',
            borderRadius: '5px',
            lineHeight: '1.2',
          }}
        >
          {perk.cost}
        </Box>
      </Box>
    </Tooltip>
  );
};
