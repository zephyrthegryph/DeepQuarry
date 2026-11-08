/**
 * The right panel's layout: five views instead of one tab per verb category.
 * Status, Actions and Game for everyone; Staff and Server for admins. Every
 * verb category maps to one view and one group here (layout.test.ts holds the
 * known categories to it); a category nobody mapped lands in Actions under its
 * own name, so a new verb is never lost.
 */

export type PanelView = 'Status' | 'Actions' | 'Game' | 'Staff' | 'Server';

/** The Server view's sub-pages. */
export type ServerPage = 'Health' | 'Tools' | 'Queries';

export const PLAYER_VIEWS: PanelView[] = ['Status', 'Actions', 'Game'];
export const ADMIN_VIEWS: PanelView[] = [
  'Status',
  'Actions',
  'Game',
  'Staff',
  'Server',
];

type Place = { view: PanelView; group: string };

/** Category (as the verb declares it, "Head.Sub" or "Head") to its place. Order inside a view is GROUP_ORDER's. */
const CATEGORY_PLACES: Record<string, Place> = {
  IC: { view: 'Actions', group: 'In character' },
  'IC.Game': { view: 'Actions', group: 'Round' },
  'IC.Event': { view: 'Actions', group: 'Round' },
  'IC.Antag': { view: 'Actions', group: 'Round' },
  'IC.Chat': { view: 'Actions', group: 'In character' },
  'IC.Mob': { view: 'Actions', group: 'In character' },
  'IC.Subtle': { view: 'Actions', group: 'In character' },
  'IC.Notes': { view: 'Actions', group: 'In character' },
  'IC.Settings': { view: 'Actions', group: 'In character' },
  'IC.Vore': { view: 'Actions', group: 'Vore' },
  'IC.NIF': { view: 'Actions', group: 'NIF' },
  'OOC.Game': { view: 'Actions', group: 'Round' },
  'OOC.Vore': { view: 'Actions', group: 'Round' },
  'OOC.Chat': { view: 'Actions', group: 'Round' },
  'OOC.Debug': { view: 'Game', group: 'Connection' },
  'Ghost.Game': { view: 'Actions', group: 'Ghost' },
  'AI.Commands': { view: 'Actions', group: 'AI' },
  'AI.Vore': { view: 'Actions', group: 'Vore' },
  // Staff
  Admin: { view: 'Staff', group: 'Your admin session' },
  'Admin.Misc': { view: 'Staff', group: 'Your admin session' },
  'Admin.Chat': { view: 'Staff', group: 'Talk' },
  'Server.Chat': { view: 'Staff', group: 'Talk' },
  'Admin.Game': { view: 'Staff', group: 'Players' },
  'Admin.Silicon': { view: 'Staff', group: 'Players' },
  'Admin.Moderation': { view: 'Staff', group: 'Players' },
  'Admin.Investigate': { view: 'Staff', group: 'Investigate' },
  'Admin.Logs': { view: 'Staff', group: 'Investigate' },
  'Admin.Secrets': { view: 'Staff', group: 'Investigate' },
  'Admin.IPIntel': { view: 'Staff', group: 'Investigate' },
  'Admin.Events': { view: 'Staff', group: 'Events' },
  'Admin.Shuttle': { view: 'Staff', group: 'Events' },
  'Fun.Drop Pod': { view: 'Staff', group: 'Events' },
  'Fun.Add Nif': { view: 'Staff', group: 'Events' },
  'Fun.Silicon': { view: 'Staff', group: 'Events' },
  'Fun.Event Kit': { view: 'Staff', group: 'Event kit' },
  'Fun.Narrate': { view: 'Staff', group: 'Narrate and sound' },
  'Fun.Sounds': { view: 'Staff', group: 'Narrate and sound' },
  'Fun.Do Not': { view: 'Staff', group: 'Destructive' },
  // Server
  'Server.Game': { view: 'Server', group: 'Round control' },
  'Server.Config': { view: 'Server', group: 'Configuration' },
  'Server.Admin': { view: 'Server', group: 'Configuration' },
  Server: { view: 'Server', group: 'Configuration' },
  'Debug.Investigate': { view: 'Server', group: 'Debug: investigate' },
  Profile: { view: 'Server', group: 'Debug: investigate' },
  Debug: { view: 'Server', group: 'Debug: game' },
  'Debug.Game': { view: 'Server', group: 'Debug: game' },
  'Debug.Events': { view: 'Server', group: 'Debug: world and tools' },
  'Debug.Misc': { view: 'Server', group: 'Debug: world and tools' },
  'Debug.Assets': { view: 'Server', group: 'Debug: world and tools' },
  'Debug.Server': { view: 'Server', group: 'Debug: world and tools' },
  'Debug.Sprites': { view: 'Server', group: 'Debug: world and tools' },
  'Debug.Dangerous': { view: 'Server', group: 'Debug: dangerous' },
  Mapping: { view: 'Server', group: 'Mapping' },
  'Mapping.Atmos': { view: 'Server', group: 'Mapping' },
  'Mapping.Testserver Only': { view: 'Server', group: 'Mapping' },
};

/** The categories layout.test.ts checks are mapped (every one a verb declares on master). */
export const KNOWN_CATEGORIES = Object.keys(CATEGORY_PLACES);

/** Groups shown in this order within their view; any other group follows, by name. */
const GROUP_ORDER: string[] = [
  'Abilities',
  'In character',
  'Round',
  'Ghost',
  'AI',
  'NIF',
  'Vore',
  'Talk',
  'Players',
  'Investigate',
  'Events',
  'Event kit',
  'Narrate and sound',
  'Destructive',
  'Your admin session',
  'Round control',
  'Configuration',
  'Debug: investigate',
  'Debug: game',
  'Debug: world and tools',
  'Debug: dangerous',
  'Mapping',
  'Connection',
];

/** Groups that start closed: long, rare or dangerous. */
export const CLOSED_BY_DEFAULT = new Set([
  'Event kit',
  'Destructive',
  'Debug: investigate',
  'Debug: game',
  'Debug: world and tools',
  'Debug: dangerous',
  'Mapping',
]);

/** Groups whose verbs are drawn as dangerous. */
export const DANGER_GROUPS = new Set(['Destructive', 'Debug: dangerous']);

/** Where a verb category goes. With the old "split admin tabs" setting gone, "Admin.Game" and "Admin" both go to Staff. */
export function placeOf(category: string): Place {
  const known = CATEGORY_PLACES[category];
  if (known) return known;
  const head = category.split('.')[0];
  const byHead = CATEGORY_PLACES[head];
  if (byHead)
    return { view: byHead.view, group: category.split('.')[1] || byHead.group };
  return { view: 'Actions', group: category.replace('.', ': ') };
}

export function groupRank(group: string): number {
  const index = GROUP_ORDER.indexOf(group);
  return index === -1 ? GROUP_ORDER.length : index;
}

/**
 * The server-side stat tab a view needs while it is shown: the server sends a
 * tab's data only while that tab is the client's stat_tab (Status lines,
 * tickets, the MC panel, SDQL2 queries). A view with no server data names
 * itself; the server ignores a name it does not know.
 */
export function dataTabOf(view: PanelView, server: ServerPage): string {
  if (view === 'Status') return 'Status';
  if (view === 'Staff') return 'Tickets';
  if (view === 'Server') {
    if (server === 'Health') return 'MC';
    if (server === 'Queries') return 'SDQL2';
    return 'Server';
  }
  return view;
}

/** Stat tabs drawn as a card over the current view instead of taking the panel over. */
export function isOverlayTab(tab: string, turfName: string): boolean {
  return (
    tab === 'Examine' || tab === 'Inspect' || (!!turfName && tab === turfName)
  );
}
