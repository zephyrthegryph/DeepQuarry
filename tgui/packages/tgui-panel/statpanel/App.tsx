import {
  Component,
  type MouseEvent,
  type ReactNode,
  useState,
  useSyncExternalStore,
} from 'react';
import { Button, Input, Section, Tabs } from 'tgui-core/components';
import { useChatScanlines } from '../consoleScanlines';
import { MapSplitHandle } from '../layout/ChatLayout';
import { AbilitiesTab } from './AbilitiesTab';
import { DockArea } from './DockArea';
import { InspectTab } from './InspectTab';
import { McTab } from './McTab';
import { MenuPage } from './MenuPage';
import {
  type State,
  type StatStore,
  searchVerbs,
  type Verb,
  verbCommand,
  verbsOfTab,
  visibleTabs,
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

function VerbTab({ state, tab }: { state: State; tab: string }) {
  return (
    <>
      {verbsOfTab(state, tab).map(({ group, verbs }) =>
        group ? (
          <Section key={group} title={group}>
            <VerbGrid verbs={verbs} />
          </Section>
        ) : (
          <VerbGrid key="" verbs={verbs} />
        ),
      )}
    </>
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

function Content({ state, store }: { state: State; store: StatStore }) {
  const tab = state.currentTab;
  const token = state.hrefToken;
  if (tab === 'Status') {
    return (
      <>
        {state.statusParts.map((part, index) =>
          part.trim() ? (
            <div className="status-line" key={index}>
              {part}
            </div>
          ) : (
            <br key={index} />
          ),
        )}
      </>
    );
  }
  if (tab === 'MC') {
    return (
      <McTab parts={state.mcParts} metrics={state.mcMetrics} token={token} />
    );
  }
  if (tab === 'Tickets') {
    return (
      <LinkTable
        rows={state.tickets}
        href={(row) =>
          row[2]
            ? `byond://?_src_=holder;admin_token=${token};ahelp=${row[2]};ahelp_action=ticket;statpanel_item_click=left;action=ticket`
            : row[3]
              ? `byond://?src=${row[3]};statpanel_item_click=left`
              : null
        }
      />
    );
  }
  if (tab === 'SDQL2') {
    return (
      <LinkTable
        rows={state.sdql2}
        href={(row) =>
          row[2] ? `byond://?src=${row[2]};statpanel_item_click=left` : null
        }
      />
    );
  }
  if (tab === 'Abilities') {
    return (
      <AbilitiesTab data={state.abilities} receivedAt={state.abilitiesAt} />
    );
  }
  if (tab === 'Inspect') return <InspectTab data={state.inspect} />;
  if (tab === 'Examine') return <Examine lines={state.examine} />;
  if (tab === 'Debug Stat Panel') return <Debug state={state} store={store} />;
  if (tab === state.turfName) return <TurfList contents={state.turfContents} />;
  if (state.misc[tab]) return <Misc rows={state.misc[tab]} />;
  if (state.spells.some((spell) => spell[0] === tab)) {
    return (
      <LinkTable
        rows={state.spells
          .filter((spell) => spell[0] === tab)
          .map((spell) => spell.slice(1))}
        href={(row) =>
          row[2] ? `byond://?src=${row[2]};statpanel_item_click=left` : null
        }
      />
    );
  }
  return <VerbTab state={state} tab={tab} />;
}

export function App(props: {
  store: StatStore;
  displayStore: {
    subscribe: (listener: () => void) => () => void;
    get: () => string;
  };
}) {
  const { store, displayStore } = props;
  useSyncExternalStore(store.subscribe, store.getVersion);
  const tabsStyle = useSyncExternalStore(
    displayStore.subscribe,
    displayStore.get,
  );
  useChatScanlines();
  const [query, setQuery] = useState('');
  const [menuOpen, setMenuOpen] = useState(false);
  const { state } = store;
  const found = searchVerbs(state, query);
  return (
    <div className="stat-root">
      <MapSplitHandle />
      <DockArea />
      <div className={`stat-tabs stat-tabs--${tabsStyle}`}>
        <Tabs className="stat-tabs__list">
          {visibleTabs(state).map((tab) => (
            <Tabs.Tab
              key={tab}
              selected={!menuOpen && tab === state.currentTab}
              onClick={() => {
                setQuery('');
                setMenuOpen(false);
                store.setTab(tab);
              }}
            >
              {tab}
            </Tabs.Tab>
          ))}
          <Tabs.Tab selected={menuOpen} onClick={() => setMenuOpen(!menuOpen)}>
            Menu
          </Tabs.Tab>
        </Tabs>
        <Input
          className="stat-search"
          placeholder="Search verbs..."
          value={query}
          onChange={setQuery}
        />
      </div>
      <div className="stat-content">
        {menuOpen ? (
          <MenuPage />
        ) : query.trim() ? (
          found.length ? (
            <VerbGrid verbs={found} />
          ) : (
            <div className="stat-empty">No verb matches.</div>
          )
        ) : (
          <Content state={state} store={store} />
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
