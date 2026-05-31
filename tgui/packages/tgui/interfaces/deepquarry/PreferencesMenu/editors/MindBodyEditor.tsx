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

// ─── Perk tree (tier rows of icon cards) ──────────────────────────────────────────

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
  // Tier = depth of the requires chain.
  const tiers = useMemo(() => {
    const byPath: Record<string, PerkMeta> = {};
    for (const p of tree.perks) {
      const meta = perks[p];
      if (meta) byPath[p] = meta;
    }
    const tierFor = (path: string, visiting = new Set<string>()): number => {
      const meta = byPath[path];
      if (!meta) return 0;
      if (!meta.requires.length) return 0;
      if (visiting.has(path)) return 0;
      visiting.add(path);
      return 1 + Math.max(...meta.requires.map((r) => tierFor(r, visiting)));
    };
    const out: { path: string; meta: PerkMeta }[][] = [];
    for (const path of Object.keys(byPath)) {
      const t = tierFor(path);
      if (!out[t]) out[t] = [];
      out[t].push({ path, meta: byPath[path] });
    }
    for (const row of out) {
      if (row) row.sort((a, b) => a.meta.cost - b.meta.cost);
    }
    return out;
  }, [tree, perks]);

  const accent = tree.color ?? categoryColor;
  return (
    <Box>
      {tiers.map(
        (row, tierIdx) =>
          row && (
            <Box key={`tier-${tierIdx}`} mb={0.5}>
              {tierIdx > 0 && (
                <Box
                  style={{
                    height: '8px',
                    marginLeft: '24px',
                    borderLeft: `2px dashed ${accent}`,
                    opacity: 0.5,
                  }}
                />
              )}
              <Stack wrap>
                {row.map(({ path, meta }) => {
                  const selected = selectedPaths.includes(path);
                  const requiresOk = meta.requires.every((r) =>
                    selectedPaths.includes(r),
                  );
                  const affordable = selected || remaining >= meta.cost;
                  const disabled =
                    !selected && (!requiresOk || !affordable);
                  return (
                    <Stack.Item key={path}>
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
                          send(
                            act,
                            selected ? 'remove_perk' : 'add_perk',
                            { perk_path: path },
                          )
                        }
                      />
                    </Stack.Item>
                  );
                })}
              </Stack>
            </Box>
          ),
      )}
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
        mr={0.5}
        mb={0.25}
        onClick={clickable ? onClick : undefined}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
        style={{
          cursor: clickable ? 'pointer' : 'default',
          width: '74px',
          padding: '4px',
          borderRadius: '6px',
          background: bg,
          border,
          opacity: disabled ? 0.55 : 1,
          transition: 'all 120ms',
          boxShadow: selected
            ? `0 0 6px ${accent}66`
            : hover && !disabled
              ? `0 0 4px ${accent}44`
              : 'none',
          textAlign: 'center',
        }}
      >
        <Box style={{ position: 'relative', height: '32px' }}>
          <Icon
            name={perk.icon}
            size={1.7}
            style={{
              color: selected ? accent : disabled ? 'rgba(255,255,255,0.3)' : accent,
              lineHeight: '32px',
            }}
          />
          {selected && (
            <Box
              style={{
                position: 'absolute',
                top: 0,
                right: 0,
                background: accent,
                borderRadius: '50%',
                width: '14px',
                height: '14px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '0.65em',
                color: '#fff',
                boxShadow: '0 0 4px rgba(0,0,0,0.6)',
              }}
            >
              <Icon name="check" />
            </Box>
          )}
          {!selected && disabled && (
            <Box
              style={{
                position: 'absolute',
                top: 0,
                right: 0,
                background: 'rgba(0,0,0,0.6)',
                borderRadius: '50%',
                width: '14px',
                height: '14px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '0.65em',
                color: 'rgba(255,255,255,0.7)',
              }}
            >
              <Icon name="lock" />
            </Box>
          )}
        </Box>
        <Box
          fontSize="0.7em"
          mt={0.25}
          style={{
            color: selected ? '#fff' : 'rgba(255,255,255,0.85)',
            fontWeight: selected ? 'bold' : 'normal',
            lineHeight: '1.1',
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
          }}
        >
          {perk.name}
        </Box>
        <Box
          fontSize="0.65em"
          style={{
            color: accent,
            fontWeight: 'bold',
            opacity: 0.8,
          }}
        >
          {perk.cost} pt{perk.cost === 1 ? '' : 's'}
        </Box>
      </Box>
    </Tooltip>
  );
};
