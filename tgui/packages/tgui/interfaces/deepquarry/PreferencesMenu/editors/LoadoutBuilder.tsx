// DQAdd — Unified loadout panel. Integrates the gear catalog, starting-kit defaults
// (headset/bag/PDA/ringtone/no-jacket/comm-visible), and underwear picker into one place
// so the player has a single Loadout tab instead of three sibling sections.
//
// Layout:
//   ┌────────────────────────────────────────────────────────────────────┐
//   │ Starting Kit strip (dropdowns + toggles)                           │
//   │ Budget bar  |  Clear                                               │
//   │ One-line ghost explainer                                           │
//   ├────────────────┬───────────────────────────────────────────────────┤
//   │ Paper doll     │ Catalog (independent scroll)                      │
//   │ Buckets        │   slot-filtered item rows                         │
//   │ Underwear row  │                                                   │
//   └────────────────┴───────────────────────────────────────────────────┘
//
// Datum selector popups (currently just Underwear) take the entire window via a
// position:fixed Dimmer with inset:0. This way the thumbnail grid actually has room
// to breathe instead of being trapped in a 200px-wide left column.
//
// Local optimistic state mirrors the server's by_body_slot / total_cost so adds and
// removes land instantly; the server is still authoritative and our op queue drops
// each entry once the server reflects it.

import { useEffect, useMemo, useRef, useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  ColorBox,
  DmIcon,
  Dropdown,
  Input,
  ProgressBar,
  Stack,
  TextArea,
  Tooltip,
} from 'tgui-core/components';
import { ColorizedImage, ColorizedImageButton } from '../helper_components';
import type { EditorProps } from './index';

type BodySlot = {
  id: number | string;
  label: string;
  group: string;
  multi?: boolean;
};

type GearTweakKind =
  | 'text'
  | 'textarea'
  | 'color'
  | 'choice'
  | 'boolean'
  | 'tf_toggle'
  | 'modal_button'
  | 'recolor'
  | 'modal';

type RecolorMeta = {
  mode: 'off' | 'tint' | 'palette' | 'matrix';
  value?: string | Record<string, string> | number[];
};

type GearTweakDescriptor = {
  key: string; // stable 1-based gear_tweaks index, as a string
  label: string; // e.g. "Color", "Custom Name", "Variant"
  kind: GearTweakKind;
  /// When true, render side-by-side as a compact button at the bottom of the customize
  /// panel instead of a full-width row. Set on the DM side for boolean/tf_toggle/modal_button.
  compact: boolean;
  choices?: string[]; // present for "choice" kind
  /// For "recolor" kind: the gear's source-icon palette (top N distinct hex colors),
  /// used to render the palette-swap swatch grid.
  palette?: string[];
};

type CatalogItem = {
  name: string;
  desc: string;
  cost: number;
  allowed_roles: string[] | null;
  show_roles: boolean;
  body_slot: string;
  tweaks: GearTweakDescriptor[];
};

type StartingKitData = {
  ringtone: string;
  comm_visible: boolean;
};

type StartingKitStatic = {
  ringtone_choices: string[];
};

type UnderwearItem = {
  name: string;
  icon?: string | null;
  icon_state?: string | null;
};

type UnderwearData = { selections: Record<string, string> };
type UnderwearStatic = { categories: Record<string, UnderwearItem[]> };

type LoadoutEntry = {
  key: string; // "_default" or a job title
  label: string; // displayed label
  priority?: string; // "high"|"med"|"low" (only on per-job entries)
  count: number;
  cost: number;
};

type LoadoutData = {
  loadout_key: string;
  loadouts: LoadoutEntry[];
  prioritized_jobs: string[];
  pda_slot: string | null;
  by_body_slot: Record<string, string[]>;
  /** Inherited (from-default) items grouped by body slot, used by SlotCell to render
   *  them as italic ghost subtext alongside the slot label. Only populated when
   *  editing a per-job loadout; empty when editing Default itself. */
  inherited_by_body_slot: Record<string, string[]>;
  /** {gear_name: {tweak_key: "Color: red" / "Custom Name: Bob's Hat"}} — pre-formatted
   *  display strings from the DM side's gear_tweak.get_contents(). Used for "modal"
   *  kind fallback display. */
  tweak_values_by_item: Record<string, Record<string, string>>;
  /** {gear_name: {tweak_key: raw_value}} — scalar metadata values for inline widgets
   *  (text input, dropdown, color picker, boolean). List/null values are omitted. */
  tweak_meta_by_item: Record<string, Record<string, string | number | boolean>>;
  /** {gear_name: {icon: byond_ref, icon_state: str}} — used by SlotCell to render the
   *  actual item sprite over the HUD slot icon when something is equipped. */
  icon_data_by_item: Record<string, { icon: string; icon_state: string }>;
  /** Item names that came from the Default loadout (and were not overridden by the
   *  current per-job loadout). Used to mark them as inherited in the UI. */
  inherited_items: string[];
  total_cost: number;
  max_gear_cost: number;
  job_defaults: Record<string, string>;
  preview_job: string | null;
  starting_kit: StartingKitData;
  underwear: UnderwearData;
};

type LoadoutStatic = {
  categories: Record<string, CatalogItem[]>;
  body_slots: BodySlot[];
  starting_kit: StartingKitStatic;
  underwear: UnderwearStatic;
};

const sendTo = (
  act: ReturnType<typeof useBackend>['act'],
  editor: string,
  action: string,
  params: Record<string, unknown> = {},
) => act('dq_editor_action', { editor, action, params });

const bodySlotKey = (slot: { id: number | string }) => String(slot.id);

const OTHER_BUCKET: BodySlot = {
  id: 'other',
  label: 'Other',
  group: 'Other',
  multi: true,
};

const HUD_ICON = 'icons/mob/screen/midnight.dmi';

// Valid icon_states in screen/midnight.dmi (matches the in-game inventory HUD).
const SLOT_HUD: Record<string, string> = {
  '12': 'hair',
  '9': 'glasses',
  '10': 'mask',
  '16': 'ears',
  '17': 'ears',
  '15': 'center',
  '14': 'suit',
  '11': 'gloves',
  '13': 'shoes',
  '3': 'back',
  '4': 'belt',
  '5': 'id',
  '7': 'pocket',
  '8': 'pocket',
  '6': 'suitstore',
};

// Paper-doll grid (3 columns, head→toe). Compact 5-row layout — all cells visible at
// the default window size without a scrollbar. Slots removed per request: ID (5), suit
// storage (6), right ear (17), left/right pocket (7, 8).
//   '_acc'    = Accessories (slot_tie, multi-allowed)
//   '_other'  = Other / spawn-in-backpack bucket
//   '_uw'     = Consolidated underwear slot (opens an in-panel multi-category picker)
//   null      = truly empty cell
const DOLL_GRID: Array<Array<string | null>> = [
  ['_acc', '12', '_other'], // Accessories / Head / Other
  ['9', '10', '16'], // Eyes / Mask / L.Ear
  ['15', '14', '_uw'], // Uniform / Suit / Underwear
  ['3', '4', '11'], // Back / Belt / Gloves
  [null, '13', null], // — / Shoes / —
];

type OptimisticOp = { kind: 'add' | 'remove'; item: CatalogItem; slot: string };

const applyOps = (
  base: LoadoutData,
  ops: OptimisticOp[],
  costByName: Record<string, number>,
): LoadoutData => {
  if (ops.length === 0) return base;
  const by_body_slot: Record<string, string[]> = { ...base.by_body_slot };
  for (const op of ops) {
    const cur = [...(by_body_slot[op.slot] ?? [])];
    if (op.kind === 'add') {
      if (op.slot === '19' || op.slot === 'other') {
        // multi-occupancy buckets (accessories / other): append
        if (!cur.includes(op.item.name)) cur.push(op.item.name);
      } else {
        // single-occupancy slot: the new item replaces whatever was there
        cur.length = 0;
        cur.push(op.item.name);
      }
    } else {
      const idx = cur.indexOf(op.item.name);
      if (idx >= 0) cur.splice(idx, 1);
    }
    by_body_slot[op.slot] = cur;
  }
  // Recompute the point total from the resulting slots rather than nudging it per-op. A swap
  // in a single-occupancy slot evicts the previous occupant, so adding the new item's cost
  // without subtracting the evicted one made the total climb on every swap.
  let total_cost = 0;
  for (const slot in by_body_slot) {
    for (const name of by_body_slot[slot]) {
      total_cost += costByName[name] ?? 0;
    }
  }
  return { ...base, by_body_slot, total_cost };
};

const dropdownDisplay = (
  options: Array<{ value: string; displayText: string }>,
  selected: string,
) => options.find((o) => o.value === selected)?.displayText ?? selected;

export const LoadoutBuilder = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const serverData = data as LoadoutData;
  const s = (staticData ?? {}) as LoadoutStatic;

  const bodySlots: BodySlot[] = [...(s.body_slots ?? []), OTHER_BUCKET];

  // Always have a slot selected. Default to Uniform (most common starting point) if it
  // exists, otherwise the first body slot in the table.
  const defaultSlot =
    bodySlots.find((b) => bodySlotKey(b) === '15')?.id ?? bodySlots[0]?.id;
  const [filterSlot, setFilterSlot] = useState<string>(
    defaultSlot != null ? String(defaultSlot) : '15',
  );

  // Always reset to the "_default" loadout when this panel mounts — switching tabs and
  // coming back shouldn't strand the editor on a per-job loadout the user no longer cares
  // about. Fires once per mount; CategoryPage unmounts the editor when the user navigates
  // to another tab, so re-entering the Loadout tab re-fires this.
  useEffect(() => {
    sendTo(act, 'loadout', 'set_loadout_key', { key: '_default' });
  }, []);

  // Optimistic ops — drop each op once the server reflects its intended outcome.
  const [pending, setPending] = useState<OptimisticOp[]>([]);
  const lastServerRef = useRef<string>('');
  useEffect(() => {
    const sig = JSON.stringify(serverData.by_body_slot);
    if (sig === lastServerRef.current) return;
    lastServerRef.current = sig;
    setPending((cur) =>
      cur.filter((op) => {
        const cur_slot = serverData.by_body_slot?.[op.slot] ?? [];
        const present = cur_slot.includes(op.item.name);
        return op.kind === 'add' ? !present : present;
      }),
    );
  }, [serverData.by_body_slot]);

  // s.categories is static data (server identity stable across polls); memo so we
  // don't rebuild the flattened catalog every render. ~1000 items × ~1Hz polls = a lot
  // of unnecessary work otherwise.
  const allItems: CatalogItem[] = useMemo(
    () => Object.values(s.categories ?? {}).flat(),
    [s.categories],
  );
  // name -> point cost, so applyOps can total the optimistic loadout from its resulting
  // slots instead of accumulating per-op drift.
  const costByName: Record<string, number> = useMemo(() => {
    const m: Record<string, number> = {};
    for (const it of allItems) m[it.name] = it.cost;
    return m;
  }, [allItems]);

  const d = applyOps(serverData, pending, costByName);
  const sk = d.starting_kit ?? ({} as StartingKitData);
  const sks = s.starting_kit ?? ({} as StartingKitStatic);
  const uw = d.underwear ?? ({ selections: {} } as UnderwearData);
  const uws = s.underwear ?? ({ categories: {} } as UnderwearStatic);
  // Role filter: scoped to the loadout currently being edited.
  //   "_default"   → union of every prioritized job (the default fronts all of them)
  //   <job_title>  → just that job
  // Items with no allowed_roles always pass (generic gear).
  const roleScope: Set<string> = useMemo(() => {
    if (d.loadout_key === '_default') {
      return new Set(d.prioritized_jobs ?? []);
    }
    return new Set([d.loadout_key]);
  }, [d.loadout_key, d.prioritized_jobs]);
  const visibleItems = useMemo(() => {
    const passesRole = (it: CatalogItem) => {
      if (!it.allowed_roles || it.allowed_roles.length === 0) return true;
      if (roleScope.size === 0) return true; // no priorities = show everything
      return it.allowed_roles.some((r) => roleScope.has(r));
    };
    return allItems.filter(
      (it) => it.body_slot === filterSlot && passesRole(it),
    );
  }, [allItems, roleScope, filterSlot]);

  const costPct = d.max_gear_cost > 0 ? d.total_cost / d.max_gear_cost : 0;

  const slotById = (id: string) => bodySlots.find((b) => bodySlotKey(b) === id);
  const filteredLabel =
    filterSlot === '_uw'
      ? 'Underwear'
      : (slotById(filterSlot)?.label ?? filterSlot);

  const otherOccupants = d.by_body_slot?.other ?? [];
  // DQEdit — backbag pref deleted; "no bag" sentinel is gone. The job's outfit always
  // equips a canonical backpack, so the "items in Other won't spawn" warning would
  // require checking both loadout back slot AND job's back default; not worth detecting
  // client-side. Items in Other simply go into whatever back slot ends up occupied.
  const bagWarning = false;

  const queueOp = (op: OptimisticOp) => setPending((cur) => [...cur, op]);

  // Full-window datum picker state — used for the underwear selector. `null` = closed.
  const [pickerCategory, setPickerCategory] = useState<string | null>(null);

  // The headset/backpack/PDA picks are now regular loadout gear datums in the catalog;
  // the only remaining starting-kit-style controls are ringtone and comm-visibility.
  const ringtoneOpts = (sks.ringtone_choices ?? []).map((x) => ({
    value: x,
    displayText: x,
  }));

  // Build the loadout-picker dropdown options. The "_default" entry is always first;
  // job-specific loadouts follow, ordered server-side by priority then alphabetical.
  const loadoutOpts = (d.loadouts ?? []).map((l) => ({
    value: l.key,
    displayText: `${l.label}${l.count > 0 ? ` (${l.count} item${l.count === 1 ? '' : 's'}, ${l.cost}p)` : ''}`,
  }));
  const loadoutKey = d.loadout_key ?? '_default';
  const loadoutLabel =
    loadoutOpts.find((o) => o.value === loadoutKey)?.displayText ?? loadoutKey;

  return (
    // position: relative anchors the FullWindowDatumPicker (which uses position:
    // absolute + inset: 0) to the loadout panel instead of escaping to the entire
    // tgui window. height: 100% + flex column so the two-column body below can
    // claim all remaining vertical space and the catalog scrolls internally rather
    // than triggering the wrapping Section's scrollbar.
    <Box
      style={{
        position: 'relative',
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      {/* Per-job loadout picker — switches which list is being edited. */}
      <Stack mb={0.5} align="center">
        <Stack.Item color="label" fontSize="0.85em">
          Editing loadout for:
        </Stack.Item>
        <Stack.Item grow>
          <Dropdown
            width="100%"
            selected={loadoutKey}
            displayText={loadoutLabel}
            options={loadoutOpts}
            onSelected={(v) => {
              // Reset pending optimistic ops on loadout-key switch — they were tagged
              // by (slot, item) only and would re-apply spuriously to the new loadout's
              // server data. The server write itself triggers a fresh poll where the
              // new key's state lands authoritatively.
              setPending([]);
              sendTo(act, 'loadout', 'set_loadout_key', { key: String(v) });
            }}
          />
        </Stack.Item>
        <Stack.Item color="label" fontSize="0.78em" italic>
          Default applies to any role you didn't customize.
        </Stack.Item>
      </Stack>
      {/* Budget + clear. PDA-related settings (ringtone, comm-visible) live in the PDA
          slot's catalog header now (see below); no_jacket lives in the suit slot. */}
      <Stack mb={0.5} align="center">
        <Stack.Item grow>
          <ProgressBar
            value={costPct}
            ranges={{
              good: [-Infinity, 0.6],
              average: [0.6, 0.9],
              bad: [0.9, Infinity],
            }}
          >
            {d.total_cost} / {d.max_gear_cost} pts
          </ProgressBar>
        </Stack.Item>
        <Stack.Item>
          <Button.Confirm
            compact
            color="bad"
            icon="trash"
            onClick={() => {
              setPending([]);
              sendTo(act, 'loadout', 'clear_loadout');
            }}
            tooltip="Clear all items in this loadout"
          />
        </Stack.Item>
      </Stack>

      {d.preview_job && (
        <Box mb={0.5} color="label" fontSize="0.85em">
          Grey labels = <b>{d.preview_job}</b>'s default kit. Your picks replace
          them.
        </Box>
      )}

      {/* Two-column body. flex: 1 + minHeight: 0 lets the catalog Stack.Item below
          shrink to fit the available vertical space (and its inner div get a real
          100% height to scroll inside of), instead of expanding to natural content
          height and bleeding past the panel. */}
      <Stack style={{ flex: 1, minHeight: 0 }}>
        {/* LEFT: doll grid — body slots PLUS the multi-allowed buckets (Accessories /
            Other / Underwear). Compact 56×64 cells in a 5-row layout so the whole panel
            fits within the default window height without a page scrollbar. */}
        <Stack.Item width="190px">
          <Box
            style={{
              display: 'grid',
              gridTemplateColumns: '56px 56px 56px',
              gap: '3px',
              justifyContent: 'center',
            }}
          >
            {DOLL_GRID.flatMap((row, ri) =>
              row.map((cell, ci) => {
                const cellKey = `c-${ri}-${ci}`;
                if (!cell)
                  return (
                    <Box
                      key={cellKey}
                      style={{ width: '56px', height: '56px' }}
                    />
                  );
                // Accessories bucket (slot_tie)
                if (cell === '_acc') {
                  return (
                    <MultiSlotCell
                      key={cellKey}
                      label="Accessories"
                      hudState="hair"
                      occupants={d.by_body_slot?.['19'] ?? []}
                      selected={filterSlot === '19'}
                      onClick={() => setFilterSlot('19')}
                    />
                  );
                }
                // "Other" (spawn-in-backpack) bucket
                if (cell === '_other') {
                  return (
                    <MultiSlotCell
                      key={cellKey}
                      label="Other"
                      hudState="back"
                      occupants={otherOccupants}
                      selected={filterSlot === 'other'}
                      onClick={() => setFilterSlot('other')}
                    />
                  );
                }
                // Consolidated underwear slot — click opens the in-panel multi-category
                // picker. Subtext summarises how many of the player's categories have a
                // non-default selection.
                if (cell === '_uw') {
                  const categories = Object.keys(uws.categories ?? {});
                  const selectedCount = categories.reduce(
                    (n, cat) =>
                      (uw.selections?.[cat] ?? 'None') !== 'None' ? n + 1 : n,
                    0,
                  );
                  return (
                    <UnderwearSlotCell
                      key={cellKey}
                      categoryCount={categories.length}
                      selectedCount={selectedCount}
                      selected={filterSlot === '_uw'}
                      onClick={() => setFilterSlot('_uw')}
                    />
                  );
                }
                // Regular body slot
                const bs = slotById(cell);
                if (!bs)
                  return (
                    <Box
                      key={cellKey}
                      style={{ width: '56px', height: '56px' }}
                    />
                  );
                const occupants = d.by_body_slot?.[cell] ?? [];
                return (
                  <SlotCell
                    key={cellKey}
                    bs={bs}
                    occupants={occupants}
                    inheritedOccupants={d.inherited_by_body_slot?.[cell] ?? []}
                    jobDefault={d.job_defaults?.[cell] ?? null}
                    selected={filterSlot === cell}
                    onClick={() => setFilterSlot(cell)}
                    iconDataByItem={d.icon_data_by_item ?? {}}
                  />
                );
              }),
            )}
          </Box>
        </Stack.Item>

        {/* RIGHT: catalog. Use a tgui `Stack fill vertical` with a `Stack.Item grow` for the
            scroll area — the same proven pattern as the preview pane — so the scrollable list
            gets a real bounded height. The earlier hand-rolled flex:1 chain relied on every
            tgui ancestor forwarding a definite height, which it didn't, so the list grew to
            its natural content height and the vertical scrollbar disappeared. */}
        <Stack.Item grow style={{ minHeight: 0 }}>
          <Stack fill vertical>
            <Stack.Item>
              <Box
                px={1}
                py={0.5}
                bold
                style={{
                  backgroundColor: 'rgba(255,255,255,0.05)',
                  borderRadius: '2px',
                }}
              >
                {filteredLabel}
                <Box inline ml={0.5} color="label" fontSize="0.85em">
                  ({visibleItems.length}{' '}
                  {visibleItems.length === 1 ? 'item' : 'items'})
                </Box>
              </Box>
            </Stack.Item>
            {/* PDA slot: ringtone is now a per-PDA tweak (see standard_pda's
                gear_tweaks). Comm-visible stays as a small inline toggle here because
                it's a global pref, not a per-PDA setting. */}
            {d.pda_slot && filterSlot === d.pda_slot && (
              <Stack.Item>
                <Stack align="center">
                  <Stack.Item grow color="label" fontSize="0.85em">
                    Comm visibility:
                  </Stack.Item>
                  <Stack.Item>
                    <Button
                      compact
                      selected={sk.comm_visible}
                      color={sk.comm_visible ? 'good' : undefined}
                      icon={sk.comm_visible ? 'check' : 'xmark'}
                      onClick={() =>
                        sendTo(act, 'starting_kit', 'toggle_comm_visible')
                      }
                      tooltip="Communicator visible to others"
                    >
                      {sk.comm_visible ? 'Visible' : 'Hidden'}
                    </Button>
                  </Stack.Item>
                </Stack>
              </Stack.Item>
            )}
            <Stack.Item grow style={{ minHeight: 0 }}>
              {filterSlot === '_uw' ? (
                <div
                  style={{
                    height: '100%',
                    overflowY: 'auto',
                    paddingRight: '4px',
                  }}
                >
                  <UnderwearCatalog
                    uws={uws}
                    uw={uw}
                    onPickCategory={(cat) => setPickerCategory(cat)}
                    onClear={(cat) =>
                      sendTo(act, 'underwear', 'clear', { category: cat })
                    }
                  />
                </div>
              ) : (
                <CatalogScrollList
                  visibleItems={visibleItems}
                  data={d}
                  bodySlots={bodySlots}
                  onOp={queueOp}
                  filterSlot={filterSlot}
                  loadoutKey={loadoutKey}
                />
              )}
            </Stack.Item>
          </Stack>
        </Stack.Item>
      </Stack>

      {pickerCategory && (
        <FullWindowDatumPicker
          title={`Choose ${pickerCategory}`}
          items={uws.categories?.[pickerCategory] ?? []}
          current={uw.selections?.[pickerCategory] ?? 'None'}
          onPick={(name) => {
            sendTo(act, 'underwear', 'pick', {
              category: pickerCategory,
              item: name,
            });
            setPickerCategory(null);
          }}
          onClose={() => setPickerCategory(null)}
        />
      )}
    </Box>
  );
};

/// Two lines under the slot icon:
///   1. The slot's own name (always — never replaced).
///   2. The first occupant's name (white) OR the job default (italic grey).
const SlotCell = ({
  bs,
  occupants,
  inheritedOccupants,
  jobDefault,
  selected,
  onClick,
  iconDataByItem,
}: {
  bs: BodySlot;
  occupants: string[];
  /** From-default loadout items — drawn as italic ghost subtext, never as the primary
   *  occupant. Only populated when editing a per-job loadout. */
  inheritedOccupants: string[];
  jobDefault: string | null;
  selected: boolean;
  onClick: () => void;
  iconDataByItem: Record<string, { icon: string; icon_state: string }>;
}) => {
  const slotHudState = SLOT_HUD[bodySlotKey(bs)] ?? 'block';
  const tipLines: string[] = [bs.label];
  if (occupants.length > 0) tipLines.push(...occupants);
  if (inheritedOccupants.length > 0)
    tipLines.push(...inheritedOccupants.map((n) => `${n} (from default)`));
  if (occupants.length === 0 && inheritedOccupants.length === 0 && jobDefault)
    tipLines.push(jobDefault);

  // Subtext priority order: per-job item > inherited from default > job's themed default.
  // Per-job items are bright; inherited and job defaults render italic grey.
  let subText: string | null = null;
  let subIsGhost = false;
  if (occupants.length === 1) {
    subText = occupants[0];
  } else if (occupants.length > 1) {
    subText = occupants.join(', ');
  } else if (inheritedOccupants.length > 0) {
    subText =
      inheritedOccupants.length === 1
        ? inheritedOccupants[0]
        : inheritedOccupants.join(', ');
    subIsGhost = true;
  } else if (jobDefault) {
    subText = jobDefault;
    subIsGhost = true;
  }

  const bgColor = selected
    ? 'rgba(0, 153, 0, 0.35)'
    : occupants.length > 0
      ? 'rgba(0, 153, 0, 0.15)'
      : 'rgba(255, 255, 255, 0.04)';

  // Icon priority: per-job item > inherited item > generic HUD slot icon.
  const firstOccupantIcon =
    occupants.length > 0
      ? iconDataByItem[occupants[0]]
      : inheritedOccupants.length > 0
        ? iconDataByItem[inheritedOccupants[0]]
        : undefined;

  // Full-cell icon, no text labels. Tooltip carries everything (slot label, occupants,
  // inherited items, job default). subText is retained only for the tooltip; the cell
  // itself is just the icon.
  if (subText) {
    // (already mentioned in tipLines above — nothing more to do)
  }

  return (
    <Tooltip content={tipLines.join('\n')}>
      <Box
        as="div"
        onClick={onClick}
        style={{
          width: '56px',
          height: '56px',
          backgroundColor: bgColor,
          border: selected
            ? '1px solid #0c0'
            : '1px solid rgba(255, 255, 255, 0.1)',
          borderRadius: '3px',
          cursor: 'pointer',
          userSelect: 'none',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '2px',
          boxSizing: 'border-box',
          position: 'relative',
          // Ghost cue (italic-grey effect on inherited or job-default items): wash the
          // background with a subtle tint so the player can still tell at a glance
          // that the slot's icon comes from inherited/default, not their own pick.
          opacity:
            occupants.length === 0 &&
            (inheritedOccupants.length > 0 || jobDefault)
              ? 0.6
              : 1,
        }}
      >
        {firstOccupantIcon ? (
          <ColorizedImage
            iconRef={firstOccupantIcon.icon}
            iconState={firstOccupantIcon.icon_state}
            color="#ffffff"
            size={52}
          />
        ) : (
          // DmIcon renders at natural 32px; scale it up so the slot cell isn't half-empty.
          <Box
            style={{
              transform: 'scale(1.5)',
              transformOrigin: 'center',
              imageRendering: 'pixelated',
            }}
          >
            <DmIcon icon={HUD_ICON} icon_state={slotHudState} />
          </Box>
        )}
      </Box>
    </Tooltip>
  );
};

/// Consolidated underwear slot — one cell in the doll grid, opens an in-panel
/// multi-category picker (Top / Bottom / Socks etc.) when selected as filterSlot.
const UnderwearSlotCell = ({
  categoryCount,
  selectedCount,
  selected,
  onClick,
}: {
  categoryCount: number;
  selectedCount: number;
  selected: boolean;
  onClick: () => void;
}) => {
  const bgColor = selected
    ? 'rgba(0, 153, 0, 0.35)'
    : selectedCount > 0
      ? 'rgba(0, 153, 0, 0.15)'
      : 'rgba(255, 255, 255, 0.04)';
  return (
    <Tooltip content={`Underwear (${selectedCount}/${categoryCount} set)`}>
      <Box
        as="div"
        onClick={onClick}
        style={{
          width: '56px',
          height: '56px',
          backgroundColor: bgColor,
          border: selected
            ? '1px solid #0c0'
            : '1px solid rgba(255, 255, 255, 0.1)',
          borderRadius: '3px',
          cursor: 'pointer',
          userSelect: 'none',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '2px',
          boxSizing: 'border-box',
          position: 'relative',
        }}
      >
        <Box
          style={{
            transform: 'scale(1.5)',
            transformOrigin: 'center',
            imageRendering: 'pixelated',
          }}
        >
          <DmIcon icon={HUD_ICON} icon_state="center" />
        </Box>
      </Box>
    </Tooltip>
  );
};

/// Slot cell variant for the multi-allowed buckets (Accessories, Other). Same visual
/// shape as a regular SlotCell so they line up under the doll, but the subtext shows
/// how many items are in the bucket and the cell is wider-friendly with no ghost.
const MultiSlotCell = ({
  label,
  hudState,
  occupants,
  selected,
  onClick,
}: {
  label: string;
  hudState: string;
  occupants: string[];
  selected: boolean;
  onClick: () => void;
}) => {
  const tipLines: string[] = [label];
  if (occupants.length > 0) tipLines.push(...occupants);
  else tipLines.push('empty');

  const subText =
    occupants.length === 0
      ? 'empty'
      : occupants.length === 1
        ? occupants[0]
        : `${occupants.length} items`;

  const bgColor = selected
    ? 'rgba(0, 153, 0, 0.35)'
    : occupants.length > 0
      ? 'rgba(0, 153, 0, 0.15)'
      : 'rgba(255, 255, 255, 0.04)';

  return (
    <Tooltip content={tipLines.join('\n')}>
      <Box
        as="div"
        onClick={onClick}
        style={{
          width: '56px',
          height: '56px',
          backgroundColor: bgColor,
          border: selected
            ? '1px solid #0c0'
            : '1px solid rgba(255, 255, 255, 0.1)',
          borderRadius: '3px',
          cursor: 'pointer',
          userSelect: 'none',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '2px',
          boxSizing: 'border-box',
          position: 'relative',
        }}
      >
        <Box
          style={{
            transform: 'scale(1.5)',
            transformOrigin: 'center',
            imageRendering: 'pixelated',
          }}
        >
          <DmIcon icon={HUD_ICON} icon_state={hudState} />
        </Box>
      </Box>
    </Tooltip>
  );
};

/// Recolor widget — three modes in one tweak.
///   Off — no recoloring; item spawns as-authored.
///   Tint — single multiplicative color picker. Cheap, can't darken→bright, just shifts hue.
///   Palette — per-source-color swatch picker. Recolors specific pixel-groups without
///             changing brightness, anti-aliasing artifacts withstanding.
///   Matrix — opens the legacy colormatrix modal for full per-channel control. Stays
///            as a modal because there's no good inline form for 12 sliders.
const RecolorWidget = ({
  label,
  palette,
  meta,
  onSet,
  onPickTint,
  onPickPaletteSwatch,
  onOpenMatrixModal,
}: {
  label: string;
  palette: string[];
  meta: RecolorMeta;
  onSet: (next: RecolorMeta) => void;
  onPickTint: () => void;
  onPickPaletteSwatch: (originalHex: string) => void;
  onOpenMatrixModal: () => void;
}) => {
  const mode = meta.mode;
  const setMode = (m: RecolorMeta['mode']) => {
    if (m === 'off') onSet({ mode: 'off' });
    else if (m === 'tint') onSet({ mode: 'tint', value: '#ffffff' });
    else if (m === 'palette') onSet({ mode: 'palette', value: {} });
    else if (m === 'matrix') onSet({ mode: 'matrix', value: [] });
  };

  return (
    <Box mb={0.5}>
      <Stack mb={0.25} align="center">
        <Stack.Item width="7em" color="label" fontSize="0.85em">
          {label}
        </Stack.Item>
        <Stack.Item grow>
          <Stack>
            {(['off', 'tint', 'palette', 'matrix'] as const).map((m) => (
              <Stack.Item key={m}>
                <Button
                  compact
                  selected={mode === m}
                  color={mode === m ? 'good' : undefined}
                  onClick={() => setMode(m)}
                >
                  {m[0].toUpperCase() + m.slice(1)}
                </Button>
              </Stack.Item>
            ))}
          </Stack>
        </Stack.Item>
      </Stack>
      {mode === 'tint' && (
        <Stack ml={4} align="center" mb={0.25}>
          <Stack.Item>
            <ColorBox color={String(meta.value ?? '#ffffff')} />
          </Stack.Item>
          <Stack.Item grow>
            <Button fluid compact icon="palette" onClick={onPickTint}>
              {String(meta.value ?? '#ffffff')}
            </Button>
          </Stack.Item>
        </Stack>
      )}
      {mode === 'palette' && (
        <Box ml={4} mb={0.25}>
          {palette.length === 0 ? (
            <Box italic color="label" fontSize="0.85em">
              No distinct colors found in this item's icon.
            </Box>
          ) : (
            <Stack wrap>
              {palette.map((orig) => {
                const cur =
                  (meta.value as Record<string, string> | undefined)?.[orig] ??
                  orig;
                const changed = cur !== orig;
                return (
                  <Stack.Item key={orig} mr={0.5} mb={0.25}>
                    <Stack align="center">
                      <Stack.Item>
                        <ColorBox color={orig} />
                      </Stack.Item>
                      <Stack.Item>→</Stack.Item>
                      <Stack.Item>
                        <Button
                          compact
                          color={changed ? 'good' : undefined}
                          tooltip={`Recolor ${orig} → ${cur}`}
                          onClick={() => onPickPaletteSwatch(orig)}
                        >
                          <ColorBox color={cur} />
                        </Button>
                      </Stack.Item>
                    </Stack>
                  </Stack.Item>
                );
              })}
            </Stack>
          )}
        </Box>
      )}
      {mode === 'matrix' && (
        <Box ml={4} mb={0.25}>
          <Stack align="center">
            <Stack.Item grow color="label" fontSize="0.85em">
              {Array.isArray(meta.value) && meta.value.length >= 12
                ? 'Matrix is set.'
                : 'No matrix set yet.'}
            </Stack.Item>
            <Stack.Item>
              <Button compact icon="palette" onClick={onOpenMatrixModal}>
                Open matrix picker
              </Button>
            </Stack.Item>
          </Stack>
        </Box>
      )}
    </Box>
  );
};

/// Inline tweak widget — switches on tweak.kind. For text/textarea/color/choice/boolean,
/// renders a real input that dispatches `set_tweak_value` directly with the new value.
/// For "modal" kind (matrix recolor, contents, tablet/laptop, item_tf_spawn) falls back
/// to a Change button that triggers the legacy `set_tweak` flow (opens tgui_input_X).
const TweakRow = ({
  item,
  tweak,
  displayString,
  rawValue,
}: {
  item: CatalogItem;
  tweak: GearTweakDescriptor;
  displayString: string;
  rawValue: string | number | boolean | undefined;
}) => {
  const { act } = useBackend();

  const dispatchValue = (value: unknown) =>
    sendTo(act, 'loadout', 'set_tweak_value', {
      gear: item.name,
      tweak: tweak.key,
      value,
    });

  switch (tweak.kind) {
    case 'text': {
      return (
        <Stack mb={0.25} align="center">
          <Stack.Item width="7em" color="label" fontSize="0.85em">
            {tweak.label}
          </Stack.Item>
          <Stack.Item grow>
            <Input
              fluid
              value={String(rawValue ?? '')}
              placeholder="(default)"
              onChange={(v) => dispatchValue(v)}
            />
          </Stack.Item>
        </Stack>
      );
    }
    case 'textarea': {
      return (
        <Box mb={0.25}>
          <Box color="label" fontSize="0.85em" mb={0.25}>
            {tweak.label}
          </Box>
          <TextArea
            fluid
            height="4em"
            value={String(rawValue ?? '')}
            onChange={(v) => dispatchValue(v)}
          />
        </Box>
      );
    }
    case 'color': {
      const hex = String(rawValue ?? '#ffffff');
      // Use BYOND's tgui_color_picker via a dedicated action (same pattern as the
      // trait_picker's blood-color picker) instead of a native HTML <input type="color">.
      return (
        <Stack mb={0.25} align="center">
          <Stack.Item width="7em" color="label" fontSize="0.85em">
            {tweak.label}
          </Stack.Item>
          <Stack.Item>
            <ColorBox color={hex} />
          </Stack.Item>
          <Stack.Item grow>
            <Button
              fluid
              compact
              icon="palette"
              onClick={() =>
                sendTo(act, 'loadout', 'pick_tweak_color', {
                  gear: item.name,
                  tweak: tweak.key,
                })
              }
            >
              {hex}
            </Button>
          </Stack.Item>
        </Stack>
      );
    }
    case 'choice': {
      const choices = tweak.choices ?? [];
      const opts = choices.map((c) => ({ value: c, displayText: c }));
      const cur = String(rawValue ?? choices[0] ?? '');
      const curLabel = opts.find((o) => o.value === cur)?.displayText ?? cur;
      return (
        <Stack mb={0.25} align="center">
          <Stack.Item width="7em" color="label" fontSize="0.85em">
            {tweak.label}
          </Stack.Item>
          <Stack.Item grow>
            <Dropdown
              width="100%"
              selected={cur}
              displayText={curLabel || '—'}
              options={opts}
              onSelected={(v) => dispatchValue(String(v))}
            />
          </Stack.Item>
        </Stack>
      );
    }
    case 'boolean': {
      const on = !!rawValue;
      // Compact mode (used in the bottom button row) is just the toggle, no label column.
      return (
        <Button
          compact
          selected={on}
          color={on ? 'good' : undefined}
          icon={on ? 'check' : 'xmark'}
          tooltip={`${tweak.label}: ${on ? 'on' : 'off'}`}
          onClick={() => dispatchValue(!on)}
        >
          {tweak.label}
        </Button>
      );
    }
    case 'tf_toggle': {
      const on = !!rawValue;
      return (
        <Button
          compact
          selected={on}
          color={on ? 'good' : undefined}
          icon={on ? 'check' : 'xmark'}
          tooltip={
            on
              ? `${tweak.label}: enabled for anyone`
              : `${tweak.label}: disabled`
          }
          onClick={() => dispatchValue(!on)}
        >
          {tweak.label}
        </Button>
      );
    }
    case 'modal_button': {
      // Single-click compact button that opens the legacy tgui_input modal. Used for
      // matrix_recolor — there's no good inline form for a full color matrix.
      return (
        <Button
          compact
          icon="palette"
          tooltip={`${tweak.label}: opens the picker`}
          onClick={() =>
            sendTo(act, 'loadout', 'set_tweak', {
              gear: item.name,
              tweak: tweak.key,
            })
          }
        >
          {tweak.label}
        </Button>
      );
    }
    case 'recolor': {
      // Unified recolor widget — mode tabs + per-mode body. rawValue is the {mode, value}
      // dict straight from DM. The dedicated set_recolor action validates the value-shape
      // per mode on the way back.
      const meta = (rawValue as unknown as RecolorMeta | undefined) ?? {
        mode: 'off',
      };
      const setMeta = (next: RecolorMeta) =>
        sendTo(act, 'loadout', 'set_recolor', {
          gear: item.name,
          tweak: tweak.key,
          value: next,
        });
      return (
        <RecolorWidget
          label={tweak.label}
          palette={tweak.palette ?? []}
          meta={meta}
          onSet={setMeta}
          onPickTint={() =>
            sendTo(act, 'loadout', 'recolor_pick_tint', {
              gear: item.name,
              tweak: tweak.key,
            })
          }
          onPickPaletteSwatch={(orig) =>
            sendTo(act, 'loadout', 'recolor_pick_palette_swatch', {
              gear: item.name,
              tweak: tweak.key,
              original: orig,
            })
          }
          onOpenMatrixModal={() =>
            sendTo(act, 'loadout', 'recolor_pick_matrix', {
              gear: item.name,
              tweak: tweak.key,
            })
          }
        />
      );
    }
    default: {
      // 'modal' (the only explicit kind landing here) plus any unknown kind: keeps the
      // legacy "Change" button → tgui_input_X modal flow. Complex tweaks (matrix recolor,
      // contents, tablet/laptop, item_tf_spawn) all route through this path.
      return (
        <Stack mb={0.25} align="center">
          <Stack.Item grow fontSize="0.85em">
            <Box
              style={{
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
              }}
            >
              {displayString ? (
                // Render as text, not HTML. /datum/gear_tweak/*.get_contents() returns plain
                // labels ("Reagents: Beer"), not markup — and any user-supplied piece
                // (custom_name, custom_desc, collar_tag) is now strip_html_simple'd at write
                // time. Text rendering closes the dangerouslySetInnerHTML XSS hole without
                // losing anything meaningful.
                <Box inline>{String(displayString)}</Box>
              ) : (
                <Box inline color="grey" italic>
                  {tweak.label}: not set
                </Box>
              )}
            </Box>
          </Stack.Item>
          <Stack.Item>
            <Button
              compact
              icon="pen"
              tooltip={`Change ${tweak.label}`}
              onClick={() =>
                sendTo(act, 'loadout', 'set_tweak', {
                  gear: item.name,
                  tweak: tweak.key,
                })
              }
            >
              Change
            </Button>
          </Stack.Item>
        </Stack>
      );
    }
  }
};

/// In-panel underwear picker. Renders one row per category (Top / Bottom / Socks),
/// each with the current selection, a Change button to open the full-panel thumbnail
/// picker for that category, and a Clear button when something is set. Lives in the
/// catalog area where the regular gear list would be when filterSlot === '_uw'.
const UnderwearCatalog = ({
  uws,
  uw,
  onPickCategory,
  onClear,
}: {
  uws: UnderwearStatic;
  uw: UnderwearData;
  onPickCategory: (cat: string) => void;
  onClear: (cat: string) => void;
}) => {
  const categories = Object.entries(uws.categories ?? {});
  if (categories.length === 0) {
    return (
      <Box italic color="label">
        Your species has no underwear categories.
      </Box>
    );
  }
  return (
    <Stack vertical>
      {categories.map(([category, items]) => {
        const currentName = uw.selections?.[category] ?? 'None';
        const meta = items.find((it) => it.name === currentName);
        const hasSelection = currentName !== 'None';
        return (
          <Stack.Item key={category}>
            <Stack align="center">
              <Stack.Item width="48px" textAlign="center">
                {meta?.icon && meta.icon_state ? (
                  <ColorizedImage
                    iconRef={meta.icon}
                    iconState={meta.icon_state}
                    color="#ffffff"
                    size={32}
                  />
                ) : (
                  <Box width="32px" height="32px" />
                )}
              </Stack.Item>
              <Stack.Item width="6em" color="label" fontSize="0.85em">
                {category}
              </Stack.Item>
              <Stack.Item
                grow
                style={{
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                }}
              >
                {hasSelection ? (
                  currentName
                ) : (
                  <Box inline italic color="grey">
                    (none)
                  </Box>
                )}
              </Stack.Item>
              <Stack.Item>
                <Button
                  compact
                  icon="grip"
                  onClick={() => onPickCategory(category)}
                >
                  Change
                </Button>
              </Stack.Item>
              <Stack.Item>
                <Button
                  compact
                  color="bad"
                  icon="xmark"
                  disabled={!hasSelection}
                  onClick={() => onClear(category)}
                />
              </Stack.Item>
            </Stack>
          </Stack.Item>
        );
      })}
    </Stack>
  );
};

/// Scrollable catalog list that auto-scrolls the first equipped item into view when the
/// filter changes (different slot picked) or the active loadout changes. So if you click
/// the Uniform slot and you already have something there, you see it without hunting.
const CatalogScrollList = ({
  visibleItems,
  data,
  bodySlots,
  onOp,
  filterSlot,
  loadoutKey,
}: {
  visibleItems: CatalogItem[];
  data: LoadoutData;
  bodySlots: BodySlot[];
  onOp: (op: OptimisticOp) => void;
  filterSlot: string;
  loadoutKey: string;
}) => {
  const listRef = useRef<HTMLDivElement | null>(null);
  const rowRefs = useRef<Map<string, HTMLDivElement>>(new Map());

  // Auto-scroll ONLY when the player switches the active slot or loadout target.
  // Earlier this effect also depended on data.by_body_slot, but tgui rebuilds that
  // object every poll (~1s), so the effect was re-firing constantly and snapping the
  // scroll back. Reading current by_body_slot inside the effect is fine — we just
  // don't want it to trigger the effect on its own.
  useEffect(() => {
    const occupants = data.by_body_slot?.[filterSlot] ?? [];
    if (occupants.length === 0) return;
    const target = occupants.find((name) => rowRefs.current.has(name));
    if (!target) return;
    const targetEl = rowRefs.current.get(target);
    const container = listRef.current;
    if (!targetEl || !container) return;
    const cRect = container.getBoundingClientRect();
    const tRect = targetEl.getBoundingClientRect();
    if (tRect.top < cRect.top || tRect.bottom > cRect.bottom) {
      targetEl.scrollIntoView({ block: 'center', behavior: 'smooth' });
    }
  }, [filterSlot, loadoutKey]);

  return (
    <div
      ref={listRef}
      style={{
        height: '100%',
        overflowY: 'auto',
        paddingRight: '4px',
      }}
    >
      {visibleItems.length === 0 ? (
        <Box italic color="label">
          No items fit this slot.
        </Box>
      ) : (
        <Stack vertical>
          {visibleItems.map((item) => (
            <Stack.Item key={item.name}>
              <div
                ref={(el: HTMLDivElement | null) => {
                  if (el) rowRefs.current.set(item.name, el);
                  else rowRefs.current.delete(item.name);
                }}
              >
                <CatalogRow
                  item={item}
                  data={data}
                  bodySlots={bodySlots}
                  onOp={onOp}
                />
              </div>
            </Stack.Item>
          ))}
        </Stack>
      )}
    </div>
  );
};

const CatalogRow = ({
  item,
  data,
  bodySlots,
  onOp,
}: {
  item: CatalogItem;
  data: LoadoutData;
  bodySlots: BodySlot[];
  onOp: (op: OptimisticOp) => void;
}) => {
  const { act } = useBackend();
  const bs = bodySlots.find((b) => bodySlotKey(b) === item.body_slot);
  const occupants = data.by_body_slot?.[item.body_slot] ?? [];
  const alreadyOn = occupants.includes(item.name);
  const wouldReplace = !bs?.multi && occupants.length > 0 && !alreadyOn;
  const overBudget =
    !alreadyOn && data.total_cost + item.cost > data.max_gear_cost;

  const icon = alreadyOn ? 'check' : wouldReplace ? 'right-left' : 'plus';
  const color = alreadyOn ? 'good' : wouldReplace ? 'average' : undefined;
  const tooltip = alreadyOn
    ? 'Remove from loadout'
    : wouldReplace
      ? 'Replace the item currently in this slot'
      : bs?.multi
        ? 'Add to this slot'
        : 'Equip in this slot';

  const onAction = () => {
    if (alreadyOn) {
      onOp({ kind: 'remove', item, slot: item.body_slot });
      sendTo(act, 'loadout', 'toggle_gear', { gear: item.name });
      return;
    }
    onOp({ kind: 'add', item, slot: item.body_slot });
    if (bs && bs.id !== 'other') {
      sendTo(act, 'loadout', 'set_body_slot', {
        body_slot: bs.id,
        gear: item.name,
      });
    } else {
      sendTo(act, 'loadout', 'toggle_gear', { gear: item.name });
    }
  };

  // Customize panel is always visible when the item is equipped — no toggle gate.
  // get_contents already prefixes its own label ("Color: red", "Name: Bob's Hat"), so
  // dropping the redundant label column avoids the "Custom Name | Name: X" doubling.
  const hasTweaks = item.tweaks && item.tweaks.length > 0;
  const tweakValues = data.tweak_values_by_item?.[item.name] ?? {};
  const tweakMeta = data.tweak_meta_by_item?.[item.name] ?? {};

  return (
    <Box
      mb={alreadyOn && hasTweaks ? 0.5 : 0}
      // Force the whole row to a single GPU compositing layer so the action button
      // (which gets promoted by its opacity transition when `selected`) doesn't scroll
      // independently from the name/desc text. Without this the selected/equipped rows
      // visibly "float" behind the rest of their row during scroll.
      style={{ transform: 'translateZ(0)', contain: 'layout paint' }}
    >
      <Stack align="center">
        <Stack.Item>
          <Button
            color={color}
            icon={icon}
            disabled={overBudget && !alreadyOn && !wouldReplace}
            tooltip={overBudget && !alreadyOn ? 'Over budget' : tooltip}
            // Disable opacity transition on this button — that's what triggers the
            // compositor layer promotion that desyncs it from the row during scroll.
            style={{ transition: 'none' }}
            onClick={onAction}
          />
        </Stack.Item>
        <Stack.Item grow>
          <Box bold>
            {item.name}{' '}
            {item.cost > 0 ? (
              <Box inline color="label" fontSize="0.85em">
                · {item.cost}p
              </Box>
            ) : (
              <Box inline color="good" fontSize="0.85em">
                · free
              </Box>
            )}
          </Box>
          {item.desc && (
            <Box color="label" fontSize="0.85em">
              {item.desc}
            </Box>
          )}
          {!!item.show_roles && !!item.allowed_roles?.length && (
            <Box color="grey" fontSize="0.8em">
              Roles: {item.allowed_roles.join(', ')}
            </Box>
          )}
        </Stack.Item>
      </Stack>
      {alreadyOn && hasTweaks && (
        <Box
          mt={0.5}
          ml={4}
          px={1}
          py={0.5}
          style={{
            backgroundColor: 'rgba(255,255,255,0.04)',
            borderLeft: '2px solid #555',
            borderRadius: '2px',
          }}
        >
          {/* Full-width tweaks first (text inputs, dropdowns, color picker) … */}
          {item.tweaks
            .filter((tw) => !tw.compact)
            .map((tw) => (
              <TweakRow
                key={tw.key}
                item={item}
                tweak={tw}
                displayString={tweakValues[tw.key] ?? ''}
                rawValue={tweakMeta[tw.key]}
              />
            ))}
          {/* … then a single row of compact buttons for toggles + modal triggers. */}
          {item.tweaks.some((tw) => tw.compact) && (
            <Stack mt={0.5}>
              {item.tweaks
                .filter((tw) => tw.compact)
                .map((tw) => (
                  <Stack.Item key={tw.key}>
                    <TweakRow
                      item={item}
                      tweak={tw}
                      displayString={tweakValues[tw.key] ?? ''}
                      rawValue={tweakMeta[tw.key]}
                    />
                  </Stack.Item>
                ))}
            </Stack>
          )}
        </Box>
      )}
    </Box>
  );
};

/// Full-window modal datum picker. position:fixed with inset:0 so it escapes the parent
/// section's bounds and covers the entire tgui window — giving the thumbnail grid room
/// to actually breathe (the underwear picker was previously trapped in a 200px column).
const FullWindowDatumPicker = ({
  title,
  items,
  current,
  onPick,
  onClose,
}: {
  title: string;
  items: UnderwearItem[];
  current: string;
  onPick: (name: string) => void;
  onClose: () => void;
}) => {
  const [search, setSearch] = useState('');
  const lcSearch = search.trim().toLowerCase();
  const filtered = items.filter(
    (it) => !lcSearch || it.name.toLowerCase().includes(lcSearch),
  );

  return (
    <Box
      // Anchored to the nearest position:relative ancestor (the LoadoutBuilder root)
      // so the picker fills the loadout panel only, not the entire tgui window.
      style={{
        position: 'absolute',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        backgroundColor: 'rgba(0, 0, 0, 0.95)',
        zIndex: 10,
        display: 'flex',
        flexDirection: 'column',
        padding: '12px',
      }}
    >
      <Stack mb={1} align="center">
        <Stack.Item grow>
          <Box bold fontSize="1.1em">
            {title}
          </Box>
        </Stack.Item>
        <Stack.Item width="320px">
          <Input
            fluid
            expensive
            placeholder="Search…"
            value={search}
            onChange={(v) => setSearch(v)}
          />
        </Stack.Item>
        <Stack.Item>
          <Button icon="xmark" color="bad" onClick={onClose}>
            Close
          </Button>
        </Stack.Item>
      </Stack>
      <Box
        style={{
          flex: '1 1 auto',
          overflowY: 'auto',
          textAlign: 'center',
        }}
      >
        <Stack wrap justify="center">
          {filtered.map((it) => (
            <Stack.Item key={it.name} m={0.5}>
              {it.icon && it.icon_state ? (
                <ColorizedImageButton
                  iconRef={it.icon}
                  iconState={it.icon_state}
                  color="#ffffff"
                  tooltip={it.name}
                  selected={it.name === current}
                  onClick={() => onPick(it.name)}
                >
                  {it.name}
                </ColorizedImageButton>
              ) : (
                <Button
                  selected={it.name === current}
                  onClick={() => onPick(it.name)}
                >
                  {it.name}
                </Button>
              )}
            </Stack.Item>
          ))}
        </Stack>
      </Box>
    </Box>
  );
};
