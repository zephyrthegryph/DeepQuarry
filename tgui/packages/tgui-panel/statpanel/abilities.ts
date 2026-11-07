// The Abilities tab's logic (AbilitiesTab.tsx): the sections, the reordering, the cooldown countdown, so all of it is tested without BYOND.
// The server side is code/content/abilities/ability_panel.dm.

/** One ability, as the server sends it. */
export type AbilityEntry = {
  /** Handle of the ability on the server: what a click or a reorder names. */
  ref: string;
  /** The stable id the player's saved order uses. */
  id: string;
  name: string;
  desc: string;
  category: string;
  /** The picture's address, or null (null too when the picture is a sprite of the abilities sheet). */
  icon: string | null;
  /** The picture as the abilities sprite sheet's CSS classes (the sheet the stat panel loaded), or null. */
  icon_class?: string | null;
  cost: string | null;
  /** Deciseconds left of the cooldown when the message was sent. */
  cooldown: number;
  /** null: not a toggle; else whether it is on. */
  toggled: boolean | null;
  /** 0 to 1 while a channel is in progress, else null. */
  channel: number | null;
  /** Null when it can be used, else why not. */
  refusal: string | null;
  /** The hotkey slot (1 to 9), or null past the ninth ability. */
  slot: number | null;
};

export type Resource = {
  name: string;
  value: number;
  /** null: a plain number with no bar. */
  max: number | null;
  color?: string | null;
};

/** What the server sends for the Abilities tab. */
export type AbilitiesData = {
  abilities: AbilityEntry[];
  resources: Resource[];
  slots: number;
};

export type Section = { category: string; entries: AbilityEntry[] };

/**
 * The entries in the order they arrived, in runs of one category: the default order is by category so each category is one section, and a
 * player who interleaves categories by dragging gets a section for each run (the numbers stay in order either way).
 */
export function sectionsOf(entries: AbilityEntry[]): Section[] {
  const sections: Section[] = [];
  for (const entry of entries) {
    const last = sections.at(-1);
    if (last && last.category === entry.category) last.entries.push(entry);
    else sections.push({ category: entry.category, entries: [entry] });
  }
  return sections;
}

/** The toggles that are on. */
export function activeToggles(entries: AbilityEntry[]): AbilityEntry[] {
  return entries.filter((entry) => entry.toggled === true);
}

/** Drag-to-reorder for the ability buttons: the shared helper (tgui/dq/reorder.ts). */
export { moveBefore } from 'tgui/dq/reorder';

/** Milliseconds of cooldown left at `now`, for a message received at `receivedAt` (both Date.now() values). */
export function cooldownMs(
  entry: AbilityEntry,
  receivedAt: number,
  now: number,
): number {
  return Math.max(0, entry.cooldown * 100 - (now - receivedAt));
}

/** Why the entry cannot be used at `now`, or null when it can. The server's refusal counts only while it is not just the cooldown running out. */
export function refusalAt(
  entry: AbilityEntry,
  receivedAt: number,
  now: number,
): string | null {
  if (!entry.refusal) return null;
  if (
    entry.refusal === 'recharging' &&
    cooldownMs(entry, receivedAt, now) <= 0
  ) {
    return null;
  }
  return entry.refusal;
}

/** "3.4s" or "12s" for the countdown on a button. */
export function cooldownText(ms: number): string {
  if (ms <= 0) return '';
  const seconds = ms / 1000;
  return seconds < 10 ? `${seconds.toFixed(1)}s` : `${Math.ceil(seconds)}s`;
}

/** The hover text: the description, the cost, and the reason it cannot be used. */
export function hoverText(entry: AbilityEntry, refusal: string | null): string {
  const lines = [entry.desc];
  if (entry.cost) lines.push(`Cost: ${entry.cost}`);
  if (entry.slot) lines.push(`Hotkey slot ${entry.slot}`);
  if (refusal) lines.push(`Cannot use now: ${refusal}`);
  return lines.join('\n');
}

/** The share of a resource's bar that is filled, 0 to 1. */
export function resourceFill(resource: Resource): number {
  if (!resource.max || resource.max <= 0) return 0;
  return Math.min(1, Math.max(0, resource.value / resource.max));
}

/** Does the tab have anything to show? A mob with no abilities and no resources has no tab. */
export function hasAbilities(data: AbilitiesData | null): boolean {
  return !!data && (data.abilities.length > 0 || data.resources.length > 0);
}
