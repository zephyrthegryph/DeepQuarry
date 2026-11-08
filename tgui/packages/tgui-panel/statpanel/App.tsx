import {
  Component,
  type MouseEvent,
  type ReactNode,
  useState,
  useSyncExternalStore,
} from 'react';
import { Button, Input } from 'tgui-core/components';
import { AbilitiesTab } from './AbilitiesTab';
import { InspectTab } from './InspectTab';
import {
  CLOSED_BY_DEFAULT,
  DANGER_GROUPS,
  type PanelView,
  type ServerPage,
} from './layout';
import { McHealthPanel } from './McHealth';
import { MenuPage } from './MenuPage';
import { MENU_SECTIONS, QUICK_ITEMS, run } from './menu';
import {
  type State,
  type StatStore,
  searchAll,
  type Verb,
  verbCommand,
  verbGroupsOf,
} from './store';

/** Commands that may take focus run after our own focus handling. */
function runVerb(name: string) {
  setTimeout(() => Byond.command(verbCommand(name)), 0);
}

function clickItem(event: MouseEvent, src: string) {
  event.preventDefault();
  const params: Record<string, string | number> = {
    src,
    statpanel_item_click:
      event.button === 1 ? 'middle' : event.button === 2 ? 'right' : 'left',
  };
  if (event.shiftKey) params.statpanel_item_shiftclick = 1;
  if (event.ctrlKey) params.statpanel_item_ctrlclick = 1;
  if (event.altKey) params.statpanel_item_altclick = 1;
  Byond.topic(params);
}

function VerbGrid({ verbs }: { verbs: Verb[] }) {
  return (
    <div className="verb-grid">
      {verbs.map((verb) => (
        <div key={verb[1]} title={verb[2] || verb[1]}>
          <Button fluid ellipsis onClick={() => runVerb(verb[1])}>
            {verb[1]}
          </Button>
        </div>
      ))}
    </div>
  );
}

function Examine({ lines }: { lines: string[] }) {
  return (
    <div className="examine">
      {lines.map((line, index) => (
        <p key={index}>
          {line.split('||').map((part, partIndex) => (
            <span
              key={partIndex}
              className={partIndex % 2 ? 'spoiler' : undefined}
              // Server-built markup, as in chat.
              dangerouslySetInnerHTML={{ __html: part }}
            />
          ))}
        </p>
      ))}
    </div>
  );
}

/** Icon sources come once per ref, later updates only name the ref. */
const knownIcons = new Map<string, string>();

function iconOf(ref: string, src?: string): string | undefined {
  if (src && !knownIcons.has(ref)) knownIcons.set(ref, src);
  return knownIcons.get(ref);
}

function TurfList({ contents }: { contents: string[][] }) {
  return (
    <div>
      {contents.map((part) => (
        <div className="item-row" key={part[1]}>
          <img src={iconOf(part[1], part[2])} alt="" />
          <span
            className="item-link"
            onMouseDown={(event) => clickItem(event, part[1])}
          >
            {part[0]}
          </span>
        </div>
      ))}
    </div>
  );
}

function Misc({ rows }: { rows: any[][] }) {
  return (
    <table className="stat-table">
      <tbody>
        {rows.map((part, index) => {
          const icon = part[1] ? iconOf(part[1], part[2]) : null;
          const span = 1 + (icon ? 0 : 1) + (part[3] ? 0 : 1);
          return (
            <tr key={index}>
              <td colSpan={span}>{part[0]}</td>
              {!!icon && (
                <td colSpan={part[3] ? 1 : 2}>
                  <img src={icon} alt="" />
                </td>
              )}
              {!!part[3] && (
                <td>
                  <span
                    className={part[4] ? 'item-link' : undefined}
                    onMouseDown={
                      part[4] ? (event) => clickItem(event, part[4]) : undefined
                    }
                  >
                    {part[3]}
                  </span>
                </td>
              )}
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function LinkTable(props: {
  rows: string[][];
  href: (row: string[]) => string | null;
}) {
  return (
    <table className="stat-table">
      <tbody>
        {props.rows.map((row, index) => {
          const href = props.href(row);
          return (
            <tr key={index}>
              <td>{row[0]}</td>
              <td>{href ? <a href={href}>{row[1]}</a> : row[1]}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function Debug({ state, store }: { state: State; store: StatStore }) {
  return (
    <>
      <Button onClick={() => store.wipeVerbs()}>
        Wipe and Update All Verbs
      </Button>
      <h3>Permanent tabs</h3>
      <div>{state.permanentTabs.join(', ')}</div>
      <h3>Verbs ({state.verbs.length})</h3>
      <table className="stat-table">
        <tbody>
          {state.verbs.map((verb) => (
            <tr key={verb[1]}>
              <td>{verb[0]}</td>
              <td>{verb[1]}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}

/** The panel's search, in its tab row: runs the first of `found` on Enter. */
export function StatSearch(props: {
  query: string;
  setQuery: (query: string) => void;
  store: StatStore;
}) {
  const { query, setQuery, store } = props;
  useSyncExternalStore(store.subscribe, store.getVersion);
  const found = searchAll(store.state, query, MENU_SECTIONS);
  return (
    <Input
      className="stat-search"
      placeholder="Search (/)"
      value={query}
      onChange={setQuery}
      onEnter={() => {
        if (found.length) store.activate(found[0]);
        setQuery('');
      }}
      onEscape={() => setQuery('')}
    />
  );
}

/**
 * One view (or the card) failing to draw shows a short error in its place; the tab row, the search and the other views keep working,
 * and the panel never falls back to blank. Reset by a new `resetKey` (another view, another card).
 */
class ViewBoundary extends Component<
  { resetKey: string; children: ReactNode },
  { error: string | null; key: string }
> {
  state = { error: null as string | null, key: this.props.resetKey };

  static getDerivedStateFromError(error: unknown) {
    return { error: error instanceof Error ? error.message : String(error) };
  }

  static getDerivedStateFromProps(
    props: { resetKey: string },
    state: { error: string | null; key: string },
  ) {
    return props.resetKey === state.key
      ? null
      : { error: null, key: props.resetKey };
  }

  componentDidCatch(error: unknown) {
    // The panel's console is the only place this shows; the message names the section for a bug report.
    console.error(`stat panel: ${this.props.resetKey} failed to draw`, error);
  }

  render() {
    if (this.state.error === null) return this.props.children;
    return (
      <div className="stat-empty">
        This part of the panel failed to draw ({this.state.error}). Other tabs
        still work; Fix UI reloads it.
      </div>
    );
  }
}

/** The card a server push opens over the current view: examine, inspect, a turf's contents, the panel debug page. */
function overlayOf(state: State, store: StatStore): ReactNode {
  const tab = state.currentTab;
  if (tab === 'Inspect') return <InspectTab data={state.inspect} />;
  if (tab === 'Examine') return <Examine lines={state.examine} />;
  if (tab === 'Debug Stat Panel') return <Debug state={state} store={store} />;
  if (state.turfName && tab === state.turfName) {
    return <TurfList contents={state.turfContents} />;
  }
  return null;
}

function OverlayCard(props: {
  title: string;
  onClose: () => void;
  children: ReactNode;
}) {
  return (
    <div className="stat-card">
      <div className="stat-card__head">
        <span className="stat-card__title">{props.title}</span>
        <button
          type="button"
          className="stat-card__close"
          title="Close"
          onClick={props.onClose}
        >
          ×
        </button>
      </div>
      <div className="stat-card__body">{props.children}</div>
    </div>
  );
}

const GROUP_STATE_KEY = 'statpanel-groups';

function loadGroupState(): Record<string, boolean> {
  try {
    return JSON.parse(localStorage.getItem(GROUP_STATE_KEY) || '{}');
  } catch {
    return {};
  }
}

/** A collapsible group; whether it is open is remembered per group name. */
function Group(props: { name: string; count?: number; children: ReactNode }) {
  const { name } = props;
  const [open, setOpen] = useState(() => {
    const saved = loadGroupState()[name];
    return saved === undefined ? !CLOSED_BY_DEFAULT.has(name) : saved;
  });
  const toggle = () => {
    const next = !open;
    setOpen(next);
    try {
      localStorage.setItem(
        GROUP_STATE_KEY,
        JSON.stringify({ ...loadGroupState(), [name]: next }),
      );
    } catch {
      // Storage refused (private mode): the group still toggles.
    }
  };
  return (
    <div
      className={`stat-group${DANGER_GROUPS.has(name) ? ' stat-group--danger' : ''}${open ? '' : ' stat-group--closed'}`}
    >
      <button type="button" className="stat-group__head" onClick={toggle}>
        <span className="stat-group__chev">{open ? '▾' : '▸'}</span>
        <span className="stat-group__name">{name}</span>
        {props.count !== undefined && (
          <span className="stat-group__count">{props.count}</span>
        )}
      </button>
      {open && <div className="stat-group__body">{props.children}</div>}
    </div>
  );
}

function VerbGroups({ state, view }: { state: State; view: PanelView }) {
  return (
    <>
      {verbGroupsOf(state, view).map(({ group, verbs }) => (
        <Group key={group} name={group} count={verbs.length}>
          <VerbGrid verbs={verbs} />
        </Group>
      ))}
    </>
  );
}

function ticketHref(token: string | null) {
  return (row: string[]) =>
    row[2]
      ? `byond://?_src_=holder;admin_token=${token};ahelp=${row[2]};ahelp_action=ticket;statpanel_item_click=left;action=ticket`
      : row[3]
        ? `byond://?src=${row[3]};statpanel_item_click=left`
        : null;
}

function StatusView({ state }: { state: State }) {
  return (
    <>
      <div className="stat-status">
        {state.statusParts.map((part, index) =>
          part.trim() ? (
            <div className="status-line" key={index}>
              {part}
            </div>
          ) : (
            <br key={index} />
          ),
        )}
      </div>
      <div className="stat-quick">
        {QUICK_ITEMS.map((item) => (
          <Button key={item.command} onClick={() => run(item.command)}>
            {item.label}
          </Button>
        ))}
      </div>
    </>
  );
}

function ActionsView({ state }: { state: State }) {
  const spellTabs = [...new Set(state.spells.map((spell) => spell[0]))];
  return (
    <>
      {state.abilities && (
        <Group name="Abilities">
          <AbilitiesTab data={state.abilities} receivedAt={state.abilitiesAt} />
        </Group>
      )}
      <VerbGroups state={state} view="Actions" />
      {spellTabs.map((tab) => (
        <Group key={tab} name={tab}>
          <LinkTable
            rows={state.spells
              .filter((spell) => spell[0] === tab)
              .map((spell) => spell.slice(1))}
            href={(row) =>
              row[2] ? `byond://?src=${row[2]};statpanel_item_click=left` : null
            }
          />
        </Group>
      ))}
      {Object.keys(state.misc).map((tab) => (
        <Group key={tab} name={tab}>
          <Misc rows={state.misc[tab]} />
        </Group>
      ))}
    </>
  );
}

function StaffView({ state }: { state: State }) {
  return (
    <>
      <Group name="Tickets" count={state.tickets.length}>
        {state.tickets.length ? (
          <LinkTable rows={state.tickets} href={ticketHref(state.hrefToken)} />
        ) : (
          <div className="stat-empty">No open tickets.</div>
        )}
      </Group>
      <VerbGroups state={state} view="Staff" />
    </>
  );
}

function ServerView({ state, store }: { state: State; store: StatStore }) {
  const pages: ServerPage[] = state.permanentTabs.includes('SDQL2')
    ? ['Health', 'Tools', 'Queries']
    : ['Health', 'Tools'];
  const page = pages.includes(state.serverPage) ? state.serverPage : 'Health';
  return (
    <>
      <div className="stat-subnav">
        {pages.map((p) => (
          <button
            type="button"
            key={p}
            className={p === page ? 'stat-subnav--on' : undefined}
            onClick={() => store.setView('Server', p)}
          >
            {p}
          </button>
        ))}
      </div>
      {page === 'Health' && (
        <McHealthPanel
          data={state.mcMetrics}
          token={state.hrefToken}
          location={state.mcLocation}
        />
      )}
      {page === 'Tools' && <VerbGroups state={state} view="Server" />}
      {page === 'Queries' && (
        <LinkTable
          rows={state.sdql2}
          href={(row) =>
            row[2] ? `byond://?src=${row[2]};statpanel_item_click=left` : null
          }
        />
      )}
    </>
  );
}

function ViewContent({ state, store }: { state: State; store: StatStore }) {
  switch (state.view) {
    case 'Actions':
      return <ActionsView state={state} />;
    case 'Game':
      return (
        <>
          <MenuPage />
          <VerbGroups state={state} view="Game" />
        </>
      );
    case 'Staff':
      return <StaffView state={state} />;
    case 'Server':
      return <ServerView state={state} store={store} />;
    default:
      return <StatusView state={state} />;
  }
}

/**
 * One stat panel view as a window of the right-hand column's page
 * (doc/rewrite/proposals/window_system.md section 12). The views are the
 * column's stacked tabs: activating one sets the panel's view (the server
 * sends the data of the current one), so a view shown alongside another,
 * split out of the stack, offers to switch to it.
 */
export function StatWindow(props: {
  query: string;
  store: StatStore;
  view: PanelView;
}) {
  const { store, view } = props;
  useSyncExternalStore(store.subscribe, store.getVersion);
  const { query } = props;
  const { state } = store;
  const found = searchAll(state, query, MENU_SECTIONS);
  const overlay = overlayOf(state, store);
  if (state.view !== view) {
    return (
      <div className="stat-root stat-root--embedded">
        <div className="stat-content">
          <Button onClick={() => store.setView(view)}>Show {view}</Button>
        </div>
      </div>
    );
  }
  return (
    <div className="stat-root stat-root--embedded">
      <div className="stat-content">
        {query.trim() ? (
          found.length ? (
            <div className="stat-results">
              {found.slice(0, 60).map((item) => (
                <Button
                  key={`${item.path}/${item.label}`}
                  fluid
                  onClick={() => store.activate(item)}
                >
                  {item.label}
                  <span className="stat-results__path">{item.path}</span>
                </Button>
              ))}
            </div>
          ) : (
            <div className="stat-empty">Nothing matches.</div>
          )
        ) : (
          <ViewBoundary resetKey={`${state.view}/${state.serverPage}`}>
            <ViewContent state={state} store={store} />
          </ViewBoundary>
        )}
        {overlay && !query.trim() && (
          <OverlayCard
            title={state.currentTab}
            onClose={() => store.closeCard()}
          >
            <ViewBoundary resetKey={`card/${state.currentTab}`}>
              {overlay}
            </ViewBoundary>
          </OverlayCard>
        )}
      </div>
    </div>
  );
}

/** A render error leaves the reload link rather than a blank panel. */
export class PanelBoundary extends Component<
  { children: ReactNode; onError: () => void },
  { failed: boolean }
> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  componentDidCatch() {
    this.props.onError();
  }

  render() {
    return this.state.failed ? null : this.props.children;
  }
}
