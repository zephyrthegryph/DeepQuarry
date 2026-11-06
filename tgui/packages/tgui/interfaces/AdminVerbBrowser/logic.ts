/**
 * The admin verb browser's pure logic: category grouping, search and the
 * pinned / recent lists, kept out of the component so bun can test it.
 * The server sends only the verbs this admin's rights allow
 * (code/content/admin/admin_verb_browser.dm).
 */

export type VerbRow = {
  /** The ADMIN_VERB path name, the key every action uses. */
  id: string;
  name: string;
  desc: string;
  /** Full category, e.g. "Debug.Investigate". */
  cat: string;
};

export type ToggleRow = {
  id: string;
  label: string;
  desc: string;
  group: string;
  value: boolean;
  /** False when this admin's rights allow none of the row's verbs. */
  can: boolean;
};

/** "Debug.Investigate" is listed under "Debug". */
export function topCategory(cat: string): string {
  const dot = cat.indexOf('.');
  return dot === -1 ? cat : cat.slice(0, dot);
}

/** "Debug.Investigate" has the sub-category "Investigate"; "Debug" has none. */
export function subCategory(cat: string): string {
  const dot = cat.indexOf('.');
  return dot === -1 ? '' : cat.slice(dot + 1);
}

export function byName(a: VerbRow, b: VerbRow): number {
  return a.name.localeCompare(b.name);
}

function words(query: string): string[] {
  return query.toLowerCase().split(/\s+/).filter(Boolean);
}

/** Every word of the query is in the verb's name, description or category. */
export function matchesQuery(verb: VerbRow, query: string): boolean {
  const needles = words(query);
  if (!needles.length) return true;
  const haystack = `${verb.name} ${verb.desc} ${verb.cat}`.toLowerCase();
  return needles.every((word) => haystack.includes(word));
}

/** The top-level categories with their verb counts, in name order. */
export function categoryCounts(verbs: VerbRow[]): [string, number][] {
  const counts = new Map<string, number>();
  for (const verb of verbs) {
    const top = topCategory(verb.cat);
    counts.set(top, (counts.get(top) ?? 0) + 1);
  }
  return [...counts].sort(([a], [b]) => a.localeCompare(b));
}

/** Verbs matching the query, narrowed to a category when one is picked. */
export function filterVerbs(
  verbs: VerbRow[],
  query: string,
  category: string | null,
): VerbRow[] {
  return verbs
    .filter((verb) => !category || topCategory(verb.cat) === category)
    .filter((verb) => matchesQuery(verb, query))
    .sort(byName);
}

/** One group per sub-category, the top level (empty name) first. */
export function groupBySub(
  verbs: VerbRow[],
): { sub: string; verbs: VerbRow[] }[] {
  const groups = new Map<string, VerbRow[]>();
  for (const verb of verbs) {
    const sub = subCategory(verb.cat);
    if (!groups.has(sub)) groups.set(sub, []);
    groups.get(sub)?.push(verb);
  }
  return [...groups]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([sub, list]) => ({ sub, verbs: list }));
}

/** The verbs named by `ids`, in that order; an id this admin may not use is skipped. */
export function pick(verbs: VerbRow[], ids: string[]): VerbRow[] {
  const byId = new Map(verbs.map((verb) => [verb.id, verb]));
  const found: VerbRow[] = [];
  for (const id of ids) {
    const verb = byId.get(id);
    if (verb) found.push(verb);
  }
  return found;
}

/** Toggles grouped by their `group`, in first-seen order. */
export function groupToggles(
  toggles: ToggleRow[],
): { group: string; rows: ToggleRow[] }[] {
  const groups = new Map<string, ToggleRow[]>();
  for (const toggle of toggles) {
    if (!groups.has(toggle.group)) groups.set(toggle.group, []);
    groups.get(toggle.group)?.push(toggle);
  }
  return [...groups].map(([group, rows]) => ({ group, rows }));
}

/** Toggles whose label, description or group matches every search word. */
export function filterToggles(
  toggles: ToggleRow[],
  query: string,
): ToggleRow[] {
  const needles = words(query);
  if (!needles.length) return toggles;
  return toggles.filter((toggle) => {
    const haystack =
      `${toggle.label} ${toggle.desc} ${toggle.group}`.toLowerCase();
    return needles.every((word) => haystack.includes(word));
  });
}
