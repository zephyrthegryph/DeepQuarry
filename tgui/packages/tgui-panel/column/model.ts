/**
 * The right-hand column's layout (doc/rewrite/proposals/window_system.md
 * section 12): every window in the column page (the chat, the stat panel's
 * views, docked tgui interfaces) as an ordered list of groups. A
 * group of one window is a list entry; of more, a tabbed stack. Pure: every
 * action returns a new state, and `saved` is re-snapshotted each time so it
 * always says where each interface was last seen (persisted per player).
 */

/** What a column window shows: a docked tgui interface (the chat and the stat panel are two), or the chat's stand-in until its window arrives. */
export type WindowKind = 'tgui' | 'pending';

export type DockWindow = {
  id: string;
  iface: string;
  title: string;
  kind?: WindowKind;
  /** Where in the list a window dropped on the panel goes (its drop point), over the saved place. */
  at?: number;
};

export type DockGroup = {
  id: string;
  windows: string[];
  active: string;
  collapsed: boolean;
  /** Body height in CSS pixels. */
  height: number;
};

/** Where an interface sits when it is docked again. */
export type Placement = {
  dock: boolean;
  group: string;
  order: number;
  tab: number;
  collapsed: boolean;
  height: number;
};

export type DockState = {
  windows: Record<string, DockWindow>;
  groups: DockGroup[];
  saved: Record<string, Placement>;
  nextGroup: number;
};

export const DOCK_HEIGHT_DEFAULT = 260;
export const DOCK_HEIGHT_MIN = 80;
export const DOCK_HEIGHT_MAX = 2000;
/** The saved layout's limit (the window_layout preference keeps at most this). */
export const DOCK_SAVE_MAX = 8000;

export type DockAction =
  | { type: 'open'; window: DockWindow }
  | { type: 'close'; id: string }
  | { type: 'title'; id: string; title: string }
  | { type: 'activate'; id: string }
  | { type: 'collapse'; group: string; collapsed: boolean }
  | { type: 'resize'; group: string; height: number }
  | { type: 'moveGroup'; group: string; index: number }
  | { type: 'moveWindow'; id: string; group: string; index: number }
  | { type: 'splitWindow'; id: string; index: number }
  | { type: 'orderTabs'; group: string; order: string[] }
  | { type: 'joinGroup'; group: string; into: string }
  | { type: 'load'; saved: Record<string, Placement> };

export function emptyDock(): DockState {
  return { windows: {}, groups: [], saved: {}, nextGroup: 1 };
}

const clampHeight = (h: unknown): number => {
  const n = Math.round(Number(h));
  if (!Number.isFinite(n)) {
    return DOCK_HEIGHT_DEFAULT;
  }
  return Math.min(DOCK_HEIGHT_MAX, Math.max(DOCK_HEIGHT_MIN, n));
};

const clampIndex = (index: number, length: number): number =>
  Math.min(length, Math.max(0, Math.round(Number(index)) || 0));

/** The group holding window `id`, or -1. */
export function groupIndexOf(state: DockState, id: string): number {
  return state.groups.findIndex((group) => group.windows.includes(id));
}

/** Takes window `id` out of its group; an emptied group goes. */
function detach(groups: DockGroup[], id: string): DockGroup[] {
  const out: DockGroup[] = [];
  for (const group of groups) {
    const at = group.windows.indexOf(id);
    if (at < 0) {
      out.push(group);
      continue;
    }
    const windows = group.windows.filter((w) => w !== id);
    if (!windows.length) {
      continue;
    }
    const active =
      group.active === id
        ? windows[Math.min(at, windows.length - 1)]
        : group.active;
    out.push({ ...group, windows, active });
  }
  return out;
}

/** Column window ids (col-1, col-2, ...) the server hands out: never an interface name, so never a key of `saved`. */
export const isPartId = (name: string): boolean => /^col-\d+$/.test(name);

/** Records every docked window's placement in `saved`; a window whose interface is not yet known (a placeholder) has none. */
export function snapshot(state: DockState): DockState {
  const saved = { ...state.saved };
  state.groups.forEach((group, order) => {
    group.windows.forEach((id, tab) => {
      const win = state.windows[id];
      if (!win || !win.iface) {
        return;
      }
      saved[win.iface] = {
        dock: true,
        group: group.id,
        order,
        tab,
        collapsed: group.collapsed,
        height: group.height,
      };
    });
  });
  return { ...state, saved };
}

function newGroupId(state: DockState): [string, number] {
  let next = state.nextGroup;
  const taken = new Set(state.groups.map((g) => g.id));
  while (taken.has(`g${next}`)) {
    next++;
  }
  return [`g${next}`, next + 1];
}

function open(state: DockState, window: DockWindow): DockState {
  if (state.windows[window.id]) {
    // Already docked: a new interface in the same pooled window keeps its place.
    return {
      ...state,
      windows: {
        ...state.windows,
        [window.id]: {
          id: window.id,
          iface: window.iface,
          title: window.title,
        },
      },
    };
  }
  const { at: dropAt, ...entry } = window;
  const windows = { ...state.windows, [window.id]: entry };
  const dropped = typeof dropAt === 'number' && Number.isFinite(dropAt);
  const place = dropped ? undefined : state.saved[window.iface];
  const groups = state.groups.slice();
  const joined = place ? groups.findIndex((g) => g.id === place.group) : -1;
  if (joined >= 0) {
    const group = groups[joined];
    const list = group.windows.slice();
    list.splice(clampIndex(place!.tab, list.length), 0, window.id);
    groups[joined] = { ...group, windows: list, active: window.id };
    return { ...state, windows, groups };
  }
  let id: string;
  let nextGroup = state.nextGroup;
  if (place?.group && !groups.some((g) => g.id === place.group)) {
    id = place.group;
  } else {
    [id, nextGroup] = newGroupId(state);
  }
  const group: DockGroup = {
    id,
    windows: [window.id],
    active: window.id,
    collapsed: Boolean(place?.collapsed),
    height: clampHeight(place?.height ?? DOCK_HEIGHT_DEFAULT),
  };
  const saved = state.saved[window.iface];
  if (dropped) {
    group.collapsed = false;
    group.height = clampHeight(saved?.height ?? DOCK_HEIGHT_DEFAULT);
  }
  const at = dropped
    ? clampIndex(dropAt!, groups.length)
    : place
      ? clampIndex(place.order, groups.length)
      : groups.length;
  groups.splice(at, 0, group);
  return { ...state, windows, groups, nextGroup };
}

function forget(state: DockState, id: string): DockState {
  const { [id]: _gone, ...windows } = state.windows;
  return { ...state, windows, groups: detach(state.groups, id) };
}

const mapGroup = (
  state: DockState,
  id: string,
  change: (group: DockGroup) => DockGroup,
): DockState => ({
  ...state,
  groups: state.groups.map((g) => (g.id === id ? change(g) : g)),
});

function reduce(state: DockState, action: DockAction): DockState {
  switch (action.type) {
    case 'open':
      return open(state, action.window);
    case 'close':
      return forget(state, action.id);
    case 'title': {
      const win = state.windows[action.id];
      return win
        ? {
            ...state,
            windows: {
              ...state.windows,
              [action.id]: { ...win, title: action.title },
            },
          }
        : state;
    }
    case 'activate': {
      const at = groupIndexOf(state, action.id);
      if (at < 0) {
        return state;
      }
      return mapGroup(state, state.groups[at].id, (g) => ({
        ...g,
        active: action.id,
        collapsed: false,
      }));
    }
    case 'collapse':
      return mapGroup(state, action.group, (g) => ({
        ...g,
        collapsed: action.collapsed,
      }));
    case 'resize':
      return mapGroup(state, action.group, (g) => ({
        ...g,
        height: clampHeight(action.height),
      }));
    case 'moveGroup': {
      const from = state.groups.findIndex((g) => g.id === action.group);
      if (from < 0) {
        return state;
      }
      const groups = state.groups.slice();
      const [group] = groups.splice(from, 1);
      // The index counts positions in the list before the move.
      const to = clampIndex(
        action.index > from ? action.index - 1 : action.index,
        groups.length,
      );
      groups.splice(to, 0, group);
      return { ...state, groups };
    }
    case 'moveWindow': {
      if (!state.windows[action.id]) {
        return state;
      }
      const target = state.groups.find((g) => g.id === action.group);
      if (!target) {
        return state;
      }
      const fromGroup = state.groups[groupIndexOf(state, action.id)];
      let index = action.index;
      if (fromGroup?.id === target.id) {
        const from = target.windows.indexOf(action.id);
        if (index > from) {
          index--;
        }
      }
      const groups = detach(state.groups, action.id);
      const at = groups.findIndex((g) => g.id === target.id);
      if (at < 0) {
        // The target was the window's own group and it held only this window.
        return state;
      }
      const list = groups[at].windows.slice();
      list.splice(clampIndex(index, list.length), 0, action.id);
      groups[at] = { ...groups[at], windows: list, active: action.id };
      return { ...state, groups };
    }
    case 'splitWindow': {
      const from = groupIndexOf(state, action.id);
      if (from < 0) {
        return state;
      }
      const source = state.groups[from];
      if (source.windows.length === 1) {
        return reduce(state, {
          type: 'moveGroup',
          group: source.id,
          index: action.index,
        });
      }
      // Indexes before the removal: the source group stays, so nothing shifts.
      const [id, nextGroup] = newGroupId(state);
      const groups = detach(state.groups, action.id);
      groups.splice(clampIndex(action.index, groups.length), 0, {
        id,
        windows: [action.id],
        active: action.id,
        collapsed: false,
        height: source.height,
      });
      return { ...state, groups, nextGroup };
    }
    case 'orderTabs': {
      const group = state.groups.find((g) => g.id === action.group);
      if (
        !group ||
        action.order.length !== group.windows.length ||
        !group.windows.every((id) => action.order.includes(id))
      ) {
        return state;
      }
      return mapGroup(state, group.id, (g) => ({
        ...g,
        windows: action.order.slice(),
      }));
    }
    case 'joinGroup': {
      // A whole entry dropped on another's header: its windows become that stack's last tabs.
      const source = state.groups.find((g) => g.id === action.group);
      const target = state.groups.find((g) => g.id === action.into);
      if (!source || !target || source === target) {
        return state;
      }
      const groups = state.groups
        .filter((g) => g !== source)
        .map((g) =>
          g === target
            ? {
                ...g,
                windows: [...g.windows, ...source.windows],
                active: source.active,
                collapsed: false,
              }
            : g,
        );
      return { ...state, groups };
    }
    case 'load':
      return {
        ...state,
        saved: Object.fromEntries(
          Object.entries({ ...action.saved, ...state.saved }).filter(
            ([iface]) => !isPartId(iface),
          ),
        ),
      };
  }
  return state;
}

/** Applies `action`, then records the placements. */
export function dockReduce(state: DockState, action: DockAction): DockState {
  const next = reduce(state, action);
  return next === state ? state : snapshot(next);
}

/** The docked windows not on screen: in a collapsed group or behind another tab. */
export function hiddenIds(state: DockState): string[] {
  const hidden: string[] = [];
  for (const group of state.groups) {
    for (const id of group.windows) {
      if (group.collapsed || id !== group.active) {
        hidden.push(id);
      }
    }
  }
  return hidden.sort();
}

/** The docked windows on screen, in list order. */
export function shownIds(state: DockState): string[] {
  return state.groups.filter((g) => !g.collapsed).map((g) => g.active);
}

const isPlacement = (value: unknown): value is Placement =>
  !!value &&
  typeof value === 'object' &&
  typeof (value as Placement).group === 'string';

/** The saved layout from its preference text; junk gives an empty layout. */
export function parseSaved(text: unknown): Record<string, Placement> {
  if (typeof text !== 'string' || !text) {
    return {};
  }
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return {};
  }
  const out: Record<string, Placement> = {};
  if (!raw || typeof raw !== 'object') {
    return out;
  }
  for (const [iface, value] of Object.entries(raw as object)) {
    if (isPartId(iface) || !isPlacement(value)) {
      continue;
    }
    out[iface] = {
      dock: Boolean(value.dock),
      group: value.group,
      order: Math.max(0, Math.round(Number(value.order)) || 0),
      tab: Math.max(0, Math.round(Number(value.tab)) || 0),
      collapsed: Boolean(value.collapsed),
      height: clampHeight(value.height),
    };
  }
  return out;
}

/**
 * The saved layout as preference text, within DOCK_SAVE_MAX: when it is too
 * long, floating entries go first, then the rest, until it fits.
 */
export function serializeSaved(saved: Record<string, Placement>): string {
  const entries = Object.entries(saved).sort(
    ([, a], [, b]) => Number(b.dock) - Number(a.dock),
  );
  while (entries.length) {
    const text = JSON.stringify(Object.fromEntries(entries));
    if (text.length <= DOCK_SAVE_MAX) {
      return text;
    }
    entries.pop();
  }
  return '{}';
}

/** The column's spacing (Column.scss): a header, the gap between entries, the padding round the list. */
export const COLUMN_HEAD = 24;
export const COLUMN_GAP = 3;
export const COLUMN_PAD = 6;
/** The least an expanded entry shows, and the least the filling entry (the chat) keeps. */
export const FIT_MIN = DOCK_HEIGHT_MIN;
export const FILL_MIN = 160;

/**
 * The heights the column draws its entries at, for a column `available`
 * pixels tall: the saved heights while they fit, else each expanded entry
 * cut in proportion (never under FIT_MIN), so the filling entry keeps at
 * least FILL_MIN and nothing is pushed out of reach. When even the least
 * heights do not fit (many windows on a short column), the list scrolls.
 * The saved heights are not changed: a taller column gets them back.
 */
export function fitHeights(
  groups: DockGroup[],
  fillAt: number,
  available: number,
): number[] {
  const heights = groups.map((g) => g.height);
  const expanded = groups
    .map((g, i) => i)
    .filter((i) => i !== fillAt && !groups[i].collapsed);
  const reserved =
    COLUMN_PAD +
    COLUMN_GAP * Math.max(0, groups.length - 1) +
    COLUMN_HEAD * groups.filter((g, i) => g.collapsed || i === fillAt).length +
    (fillAt >= 0 ? FILL_MIN : 0);
  const budget = Math.max(0, available - reserved);
  const wanted = expanded.reduce((sum, i) => sum + heights[i], 0);
  if (wanted <= budget || wanted === 0) return heights;
  const scale = budget / wanted;
  for (const i of expanded) {
    heights[i] = Math.max(FIT_MIN, Math.floor(heights[i] * scale));
  }
  return heights;
}
