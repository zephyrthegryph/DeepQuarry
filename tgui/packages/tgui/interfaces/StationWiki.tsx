/**
 * The station wiki (code/content/wiki/): the index on the left (departments
 * that fold open and shut, and a search with snippets), the article on the
 * right. The index comes once per open as static data; the server sends only
 * the article the reader is on. Back and forward are this window's own
 * history of ids; a page opened from outside (a reference book) lands in it.
 *
 * Article bodies are blocks (wiki.dm's header): paragraphs, headings, lists,
 * callouts, labelled facts, link rows, tables and tabs. Any text may carry
 * inline links, [[id]] or [[id|label]], and **bold**. An article with a sprite
 * or a colour swatch, or labelled facts near its top, gets an infobox card.
 *
 * Everything else is drawn here from the index alone, with no server trip:
 * the breadcrumbs, a landing page per section (cards for its subsections and
 * its articles), the home page's department cards and the "In this section"
 * list under an article. Which sections are open is kept per session.
 */

import {
  Fragment,
  type ReactNode,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { useBackend } from 'tgui/backend';
import { Tabs } from 'tgui/dq';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  DmIcon,
  Icon,
  Input,
  Tooltip,
} from 'tgui-core/components';

/** One index row: id, title, path ("Medical/Conditions/Cardiac"), summary. */
type IndexRow = [string, string, string, string];

type Link = {
  id: string | null;
  name: string;
  note?: string | null;
  tone?: string | null;
  icon?: string | null;
  icon_state?: string | null;
};

type Block =
  | { k: 'p' | 'h'; t: string }
  | { k: 'note'; t: string; tone?: string }
  | { k: 'ul' | 'ol'; items: string[] }
  | { k: 'kv'; rows: [string, string][] }
  | { k: 'links'; t: string; items: Link[] }
  | { k: 'table'; head: string[]; rows: string[][] }
  | { k: 'tabs'; tabs: { name: string; blocks: Block[] }[] };

type Article = {
  id: string;
  title: string;
  path: string;
  summary?: string | null;
  blocks: Block[];
  icon?: string | null;
  icon_state?: string | null;
  swatch?: string | null;
};

type Data = {
  index: IndexRow[];
  article: Article | null;
  requested: string;
  home: string;
};

/** Catch-all sections sort after their siblings so the useful ones come first. */
const SINKS = ['Other', 'Uncategorised', 'Miscellaneous'];
/** Top-level sections in a fixed order; the rest follow alphabetically. */
const TOP_ORDER = ['Welcome'];

export function compareSections(a: string, b: string): number {
  const ta = TOP_ORDER.indexOf(a);
  const tb = TOP_ORDER.indexOf(b);
  if (ta !== tb) return (ta < 0 ? 99 : ta) - (tb < 0 ? 99 : tb);
  const sa = SINKS.includes(a);
  const sb = SINKS.includes(b);
  if (sa !== sb) return sa ? 1 : -1;
  return a.localeCompare(b);
}

/** A department's accent colour and icon, by its top-level section name. */
type Dept = { color: string; icon: string };
const DEPTS: Record<string, Dept> = {
  Welcome: { color: '#8fa8c8', icon: 'home' },
  Medical: { color: '#4fc3e8', icon: 'kit-medical' },
  Chemistry: { color: '#e86fb0', icon: 'flask' },
  Research: { color: '#b07cf0', icon: 'microscope' },
  Engineering: { color: '#f0a33a', icon: 'wrench' },
  Security: { color: '#e8564f', icon: 'shield-halved' },
  Cargo: { color: '#d6b45a', icon: 'box' },
  Civilian: { color: '#72c45a', icon: 'users' },
  Command: { color: '#5b8ef0', icon: 'id-card' },
  Guides: { color: '#8fd0c0', icon: 'book' },
};
const DEFAULT_DEPT: Dept = { color: '#8a929c', icon: 'folder' };

export function deptOf(path: string | null | undefined): Dept {
  return DEPTS[(path || '').split('/')[0]] ?? DEFAULT_DEPT;
}

/** A callout's look by the note's tone (wiki.dm: good = tip, average = warning, bad = danger, else info). */
const CALLOUTS: Record<string, { kind: string; icon: string; label: string }> =
  {
    good: { kind: 'tip', icon: 'lightbulb', label: 'Tip' },
    green: { kind: 'tip', icon: 'lightbulb', label: 'Tip' },
    average: {
      kind: 'warning',
      icon: 'triangle-exclamation',
      label: 'Warning',
    },
    yellow: {
      kind: 'warning',
      icon: 'triangle-exclamation',
      label: 'Warning',
    },
    orange: {
      kind: 'warning',
      icon: 'triangle-exclamation',
      label: 'Warning',
    },
    bad: { kind: 'danger', icon: 'circle-exclamation', label: 'Danger' },
    red: { kind: 'danger', icon: 'circle-exclamation', label: 'Danger' },
  };
const INFO_CALLOUT = { kind: 'info', icon: 'circle-info', label: 'Note' };

export function calloutOf(tone?: string | null) {
  return (tone && CALLOUTS[tone]) || INFO_CALLOUT;
}

type Node = {
  name: string;
  key: string;
  children: Map<string, Node>;
  articles: IndexRow[];
  /** Articles in this node and every node under it. */
  count: number;
};

export function buildTree(index: IndexRow[]): Node {
  const root: Node = {
    name: '',
    key: '',
    children: new Map(),
    articles: [],
    count: 0,
  };
  for (const row of index) {
    let node = root;
    root.count++;
    for (const part of (row[2] || 'Uncategorised').split('/')) {
      const key = node.key ? `${node.key}/${part}` : part;
      let child = node.children.get(part);
      if (!child) {
        child = {
          name: part,
          key,
          children: new Map(),
          articles: [],
          count: 0,
        };
        node.children.set(part, child);
      }
      child.count++;
      node = child;
    }
    node.articles.push(row);
  }
  return root;
}

function findNode(root: Node, key: string): Node | null {
  let node: Node | undefined = root;
  for (const part of key.split('/')) {
    node = node?.children.get(part);
    if (!node) return null;
  }
  return node;
}

function sortedChildren(node: Node): Node[] {
  return [...node.children.values()].sort((a, b) =>
    compareSections(a.name, b.name),
  );
}

function sortedArticles(node: Node): IndexRow[] {
  return [...node.articles].sort((a, b) => a[1].localeCompare(b[1]));
}

/** Inline text: [[id]] / [[id|label]] links and **bold**. */
export function parseInline(
  text: string,
): (
  | { kind: 'text'; text: string }
  | { kind: 'bold'; text: string }
  | { kind: 'link'; id: string; label: string | null }
)[] {
  const out: ReturnType<typeof parseInline> = [];
  const re = /\[\[([^\]|]+)(?:\|([^\]]*))?\]\]|\*\*([^*]+)\*\*/g;
  let last = 0;
  for (let m = re.exec(text); m; m = re.exec(text)) {
    if (m.index > last)
      out.push({ kind: 'text', text: text.slice(last, m.index) });
    if (m[3] !== undefined) out.push({ kind: 'bold', text: m[3] });
    else out.push({ kind: 'link', id: m[1], label: m[2] ?? null });
    last = re.lastIndex;
  }
  if (last < text.length) out.push({ kind: 'text', text: text.slice(last) });
  return out;
}

/** Text with its markup removed, for snippets: links become their labels. */
export function plainText(text: string, titles: Map<string, string>): string {
  return parseInline(text)
    .map((part) =>
      part.kind === 'link'
        ? part.label || titles.get(part.id) || part.id
        : part.text,
    )
    .join('');
}

type Ctx = {
  titles: Map<string, string>;
  go: (id: string) => void;
};

function Inline(props: { text?: string | null; ctx: Ctx }) {
  const { text, ctx } = props;
  if (!text) return null;
  return (
    <>
      {parseInline(text).map((part, i) => {
        if (part.kind === 'text')
          return <Fragment key={i}>{part.text}</Fragment>;
        if (part.kind === 'bold') return <b key={i}>{part.text}</b>;
        const title = ctx.titles.get(part.id);
        const label = part.label || title || part.id;
        if (!title)
          return (
            <Tooltip key={i} content={`No article: ${part.id}`}>
              <span className="StationWiki__deadLink">{label}</span>
            </Tooltip>
          );
        return (
          <a
            key={i}
            className="StationWiki__link"
            href="#"
            onClick={(e) => {
              e.preventDefault();
              ctx.go(part.id);
            }}
          >
            {label}
          </a>
        );
      })}
    </>
  );
}

/** An item's sprite, or a neutral cube while it loads (and in previews, which have no icons). */
function Sprite(props: {
  icon?: string | null;
  icon_state?: string | null;
  size: number;
}) {
  const { icon, icon_state, size } = props;
  const fallback = (
    <Box
      className="StationWiki__spriteFallback"
      style={{ width: `${size}px`, height: `${size}px` }}
    >
      <Icon name="cube" />
    </Box>
  );
  if (!icon) return fallback;
  return (
    <DmIcon
      className="StationWiki__sprite"
      fallback={fallback}
      icon={icon}
      icon_state={icon_state || ''}
      width={`${size}px`}
      height={`${size}px`}
    />
  );
}

function LinkRow(props: { block: { t: string; items: Link[] }; ctx: Ctx }) {
  const { block, ctx } = props;
  return (
    <>
      <div className="StationWiki__rowLabel">
        <Inline text={block.t} ctx={ctx} />
      </div>
      <div className="StationWiki__rowItems">
        {block.items.map((item, i) => {
          const live = !!item.id && ctx.titles.has(item.id);
          const tone = item.tone ? ` StationWiki__chip--${item.tone}` : '';
          const body = (
            <>
              {item.icon ? (
                <Sprite
                  icon={item.icon}
                  icon_state={item.icon_state}
                  size={16}
                />
              ) : null}
              <span className="StationWiki__chipName">{item.name}</span>
              {item.note ? (
                <span className="StationWiki__chipNote">
                  <Inline text={item.note} ctx={ctx} />
                </span>
              ) : null}
            </>
          );
          return live ? (
            <button
              type="button"
              key={`${item.id}-${i}`}
              className={`StationWiki__chip StationWiki__chip--live${tone}`}
              onClick={() => ctx.go(item.id as string)}
            >
              {body}
            </button>
          ) : (
            <span
              key={`${item.id}-${i}`}
              className={`StationWiki__chip${tone}`}
            >
              {body}
            </span>
          );
        })}
      </div>
    </>
  );
}

function ArticleTabs(props: {
  tabs: { name: string; blocks: Block[] }[];
  ctx: Ctx;
  articleId: string;
}) {
  const [selected, setSelected] = useState(0);
  // A new article starts on its first tab.
  useEffect(() => setSelected(0), [props.articleId]);
  const current = props.tabs[Math.min(selected, props.tabs.length - 1)];
  return (
    <Box className="StationWiki__tabs">
      <Tabs
        tabs={props.tabs.map((tab, i) => ({
          id: `${i}`,
          label: tab.name,
          selected: i === selected,
        }))}
        onSelect={(id) => setSelected(Number(id))}
      />
      <Box className="StationWiki__tabBody">
        {current ? (
          <Blocks
            blocks={current.blocks}
            ctx={props.ctx}
            articleId={props.articleId}
          />
        ) : null}
      </Box>
    </Box>
  );
}

function Facts(props: { rows: [string, string][]; ctx: Ctx }) {
  return (
    <table className="StationWiki__facts">
      <tbody>
        {props.rows.map(([label, text]) => (
          <tr key={label}>
            <th>{label}</th>
            <td>
              <Inline text={text} ctx={props.ctx} />
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function Blocks(props: { blocks: Block[]; ctx: Ctx; articleId: string }) {
  const { ctx } = props;
  const out: ReactNode[] = [];
  let rows: ReactNode[] = [];
  // Consecutive link rows share one grid so their labels line up.
  const flush = (key: string) => {
    if (rows.length) {
      out.push(
        <div key={`grid-${key}`} className="StationWiki__grid">
          {rows}
        </div>,
      );
      rows = [];
    }
  };
  props.blocks.forEach((block, i) => {
    if (block.k === 'links') {
      if (block.items.length)
        rows.push(<LinkRow key={i} block={block} ctx={ctx} />);
      return;
    }
    flush(`${i}`);
    switch (block.k) {
      case 'p':
        out.push(
          <p key={i} className="StationWiki__p">
            <Inline text={block.t} ctx={ctx} />
          </p>,
        );
        break;
      case 'h':
        out.push(
          <h3 key={i} className="StationWiki__h">
            <Inline text={block.t} ctx={ctx} />
          </h3>,
        );
        break;
      case 'note': {
        const callout = calloutOf(block.tone);
        out.push(
          <div
            key={i}
            className={`StationWiki__callout StationWiki__callout--${callout.kind}`}
          >
            <Icon name={callout.icon} className="StationWiki__calloutIcon" />
            <div>
              <Inline text={block.t} ctx={ctx} />
            </div>
          </div>,
        );
        break;
      }
      case 'ul':
      case 'ol': {
        const List = block.k;
        out.push(
          <List key={i} className="StationWiki__list">
            {block.items.map((item, j) => (
              <li key={j}>
                <Inline text={item} ctx={ctx} />
              </li>
            ))}
          </List>,
        );
        break;
      }
      case 'kv':
        out.push(<Facts key={i} rows={block.rows} ctx={ctx} />);
        break;
      case 'table':
        out.push(
          <div key={i} className="StationWiki__tableWrap">
            <table className="StationWiki__table">
              <thead>
                <tr>
                  {block.head.map((cell) => (
                    <th key={cell}>{cell}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {block.rows.map((row, j) => (
                  <tr key={j}>
                    {row.map((cell, c) => (
                      <td key={c}>
                        <Inline text={cell} ctx={ctx} />
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>,
        );
        break;
      case 'tabs':
        out.push(
          <ArticleTabs
            key={i}
            tabs={block.tabs}
            ctx={ctx}
            articleId={props.articleId}
          />,
        );
        break;
    }
  });
  flush('end');
  return <>{out}</>;
}

/** The infobox's facts: the first labelled facts among an article's first three blocks (lifted out of the body). */
export function infoboxFacts(article: Article): number {
  const limit = Math.min(article.blocks.length, 3);
  for (let i = 0; i < limit; i++) if (article.blocks[i].k === 'kv') return i;
  return -1;
}

function Infobox(props: {
  article: Article;
  facts: [string, string][] | null;
  ctx: Ctx;
  openSection: (key: string) => void;
}) {
  const { article, facts, ctx } = props;
  const dept = deptOf(article.path);
  const top = (article.path || '').split('/')[0];
  return (
    <aside
      className="StationWiki__infobox"
      style={{ borderTopColor: dept.color }}
    >
      <div className="StationWiki__infoboxTitle">{article.title}</div>
      {article.icon ? (
        <div className="StationWiki__infoboxArt">
          <Sprite
            icon={article.icon}
            icon_state={article.icon_state}
            size={64}
          />
        </div>
      ) : null}
      {article.swatch ? (
        <div className="StationWiki__infoboxArt">
          <span
            className="StationWiki__swatch StationWiki__swatch--big"
            style={{ backgroundColor: article.swatch }}
          />
          <span className="StationWiki__swatchHex">{article.swatch}</span>
        </div>
      ) : null}
      {top ? (
        <div className="StationWiki__infoboxBadges">
          <button
            type="button"
            className="StationWiki__badge"
            style={{ borderColor: dept.color, color: dept.color }}
            onClick={() => props.openSection(top)}
          >
            <Icon name={dept.icon} mr={0.4} />
            {top}
          </button>
        </div>
      ) : null}
      {facts ? <Facts rows={facts} ctx={ctx} /> : null}
    </aside>
  );
}

function Breadcrumbs(props: {
  path: string;
  openSection: (key: string) => void;
  goHome: () => void;
}) {
  const parts = (props.path || '').split('/').filter(Boolean);
  const dept = deptOf(props.path);
  return (
    <nav className="StationWiki__crumbs">
      <button
        type="button"
        className="StationWiki__crumb"
        onClick={props.goHome}
        title="Front page"
      >
        <Icon name="home" />
      </button>
      {parts.map((part, i) => {
        const key = parts.slice(0, i + 1).join('/');
        return (
          <Fragment key={key}>
            <Icon name="chevron-right" className="StationWiki__crumbSep" />
            <button
              type="button"
              className="StationWiki__crumb"
              style={i === 0 ? { color: dept.color } : undefined}
              onClick={() => props.openSection(key)}
            >
              {i === 0 ? <Icon name={dept.icon} mr={0.4} /> : null}
              {part}
            </button>
          </Fragment>
        );
      })}
    </nav>
  );
}

/** A card: a subsection (with its article count) or an article (with its summary). */
function Card(props: {
  title: string;
  sub?: string | null;
  count?: number;
  color: string;
  icon: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      className="StationWiki__card"
      style={{ borderLeftColor: props.color }}
      onClick={props.onClick}
    >
      <div className="StationWiki__cardHead">
        <Icon name={props.icon} color={props.color} mr={0.5} />
        <span className="StationWiki__cardTitle">{props.title}</span>
        {props.count !== undefined ? (
          <span className="StationWiki__count">{props.count}</span>
        ) : null}
      </div>
      {props.sub ? (
        <div className="StationWiki__cardSub">{props.sub}</div>
      ) : null}
    </button>
  );
}

/** How many article cards a landing page shows before "show all". */
const LANDING_ARTICLES = 60;

function SectionLanding(props: {
  node: Node;
  ctx: Ctx;
  openSection: (key: string) => void;
}) {
  const { node, ctx } = props;
  const dept = deptOf(node.key);
  const [all, setAll] = useState(false);
  useEffect(() => setAll(false), [node.key]);
  const children = sortedChildren(node);
  const articles = sortedArticles(node);
  const shown = all ? articles : articles.slice(0, LANDING_ARTICLES);
  return (
    <>
      {children.length ? (
        <>
          <h3 className="StationWiki__h">Sections</h3>
          <div className="StationWiki__cards">
            {children.map((child) => (
              <Card
                key={child.key}
                title={child.name}
                count={child.count}
                sub={sortedArticles(child)
                  .slice(0, 3)
                  .map((row) => row[1])
                  .join(', ')}
                color={dept.color}
                icon="folder"
                onClick={() => props.openSection(child.key)}
              />
            ))}
          </div>
        </>
      ) : null}
      {articles.length ? (
        <>
          <h3 className="StationWiki__h">Articles</h3>
          <div className="StationWiki__cards">
            {shown.map((row) => (
              <Card
                key={row[0]}
                title={row[1]}
                sub={row[3] ? plainText(row[3], ctx.titles) : null}
                color={dept.color}
                icon="file-lines"
                onClick={() => ctx.go(row[0])}
              />
            ))}
          </div>
          {shown.length < articles.length ? (
            <Button mt={1} icon="angle-down" onClick={() => setAll(true)}>
              Show all {articles.length}
            </Button>
          ) : null}
        </>
      ) : null}
    </>
  );
}

function DepartmentCards(props: {
  tree: Node;
  openSection: (key: string) => void;
}) {
  return (
    <>
      <h3 className="StationWiki__h">Departments</h3>
      <div className="StationWiki__cards StationWiki__cards--depts">
        {sortedChildren(props.tree)
          .filter((node) => node.name !== 'Welcome')
          .map((node) => {
            const dept = deptOf(node.key);
            return (
              <Card
                key={node.key}
                title={node.name}
                count={node.count}
                sub={sortedChildren(node)
                  .map((child) => child.name)
                  .slice(0, 5)
                  .join(' · ')}
                color={dept.color}
                icon={dept.icon}
                onClick={() => props.openSection(node.key)}
              />
            );
          })}
      </div>
    </>
  );
}

/** How many sibling articles "In this section" lists. */
const RELATED_MAX = 12;

function Related(props: {
  article: Article;
  tree: Node;
  ctx: Ctx;
  openSection: (key: string) => void;
}) {
  const node = findNode(props.tree, props.article.path || 'Uncategorised');
  if (!node) return null;
  const siblings = sortedArticles(node).filter(
    (row) => row[0] !== props.article.id,
  );
  if (!siblings.length) return null;
  return (
    <footer className="StationWiki__related">
      <div className="StationWiki__relatedHead">
        <Icon name="layer-group" mr={0.5} />
        In this section
        <button
          type="button"
          className="StationWiki__more"
          onClick={() => props.openSection(node.key)}
        >
          {node.name} ({node.count}) <Icon name="arrow-right" />
        </button>
      </div>
      <div className="StationWiki__rowItems">
        {siblings.slice(0, RELATED_MAX).map((row) => (
          <button
            type="button"
            key={row[0]}
            className="StationWiki__chip StationWiki__chip--live"
            onClick={() => props.ctx.go(row[0])}
          >
            <span className="StationWiki__chipName">{row[1]}</span>
          </button>
        ))}
      </div>
    </footer>
  );
}

function TreeNode(props: {
  node: Node;
  depth: number;
  open: Set<string>;
  toggle: (key: string) => void;
  current: string | null;
  currentSection: string | null;
  go: (id: string) => void;
  openSection: (key: string) => void;
}) {
  const { node, depth, open, toggle, current, go } = props;
  const children = sortedChildren(node);
  const articles = sortedArticles(node);
  const body = (
    <>
      {children.map((child) => (
        <TreeNode {...props} key={child.key} node={child} depth={depth + 1} />
      ))}
      {articles.map((row) => (
        <button
          type="button"
          key={row[0]}
          className={`StationWiki__entry${row[0] === current ? ' StationWiki__entry--current' : ''}`}
          onClick={() => go(row[0])}
          style={{ paddingLeft: `${1.6 + (depth + 1) * 0.8}em` }}
          title={row[1]}
        >
          {row[1]}
        </button>
      ))}
    </>
  );
  if (depth < 0) return body;
  const isOpen = open.has(node.key);
  const dept = depth === 0 ? deptOf(node.key) : null;
  return (
    <div>
      <div
        className={`StationWiki__section${node.key === props.currentSection ? ' StationWiki__section--current' : ''}${depth === 0 ? ' StationWiki__section--top' : ''}`}
        style={{
          paddingLeft: `${0.2 + depth * 0.8}em`,
          borderLeftColor: dept ? dept.color : 'transparent',
        }}
      >
        <button
          type="button"
          className="StationWiki__fold"
          onClick={() => toggle(node.key)}
          aria-expanded={isOpen}
          title={isOpen ? 'Fold' : 'Unfold'}
        >
          <Icon name={isOpen ? 'chevron-down' : 'chevron-right'} />
        </button>
        <button
          type="button"
          className="StationWiki__sectionName"
          onClick={() => props.openSection(node.key)}
        >
          {dept ? <Icon name={dept.icon} color={dept.color} mr={0.5} /> : null}
          {node.name}
        </button>
        <span className="StationWiki__count">{node.count}</span>
      </div>
      {isOpen ? body : null}
    </div>
  );
}

/** Search: title matches first (prefix before substring), then section and summary matches. */
export function searchIndex(index: IndexRow[], query: string): IndexRow[] {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  const scored: [number, IndexRow][] = [];
  for (const row of index) {
    const title = row[1].toLowerCase();
    let score = -1;
    if (title.startsWith(q)) score = 0;
    else if (title.includes(q)) score = 1;
    else if (row[2].toLowerCase().includes(q)) score = 2;
    else if (row[3]?.toLowerCase().includes(q)) score = 3;
    if (score >= 0) scored.push([score, row]);
  }
  scored.sort((a, b) => a[0] - b[0] || a[1][1].localeCompare(b[1][1]));
  return scored.slice(0, 200).map((s) => s[1]);
}

/** `text` with the first match of `query` marked. */
function Highlight(props: { text: string; query: string }) {
  const { text, query } = props;
  const q = query.trim().toLowerCase();
  const at = q ? text.toLowerCase().indexOf(q) : -1;
  if (at < 0) return <>{text}</>;
  return (
    <>
      {text.slice(0, at)}
      <mark className="StationWiki__mark">{text.slice(at, at + q.length)}</mark>
      {text.slice(at + q.length)}
    </>
  );
}

function SearchResults(props: {
  results: IndexRow[];
  query: string;
  cursor: number;
  current: string;
  ctx: Ctx;
}) {
  const { results, query, cursor, ctx } = props;
  if (!results.length)
    return (
      <div className="StationWiki__empty">
        <Icon name="magnifying-glass" mr={0.5} />
        Nothing matches "{query.trim()}".
      </div>
    );
  return (
    <>
      <div className="StationWiki__resultCount">
        {results.length === 200 ? '200+' : results.length} result
        {results.length === 1 ? '' : 's'} · ↑↓ to pick, Enter to open
      </div>
      {results.map((row, i) => {
        const dept = deptOf(row[2]);
        const summary = row[3] ? plainText(row[3], ctx.titles) : '';
        return (
          <button
            type="button"
            key={row[0]}
            className={`StationWiki__result${i === cursor ? ' StationWiki__result--cursor' : ''}${row[0] === props.current ? ' StationWiki__result--current' : ''}`}
            style={{ borderLeftColor: dept.color }}
            onClick={() => ctx.go(row[0])}
          >
            <div className="StationWiki__resultTitle">
              <Highlight text={row[1]} query={query} />
            </div>
            <div className="StationWiki__resultPath">
              <Icon name={dept.icon} color={dept.color} mr={0.4} />
              {row[2].split('/').join(' › ')}
            </div>
            {summary ? (
              <div className="StationWiki__resultSnippet">
                <Highlight text={summary} query={query} />
              </div>
            ) : null}
          </button>
        );
      })}
    </>
  );
}

/** Which sections are open, kept for the session (sessionStorage; a page without storage just starts folded). */
const OPEN_KEY = 'StationWiki.open';

function loadOpen(): Set<string> {
  try {
    const raw = window.sessionStorage?.getItem(OPEN_KEY);
    if (raw) return new Set(JSON.parse(raw) as string[]);
  } catch {
    // No storage here (a preview, a locked-down browser): start folded.
  }
  return new Set();
}

function saveOpen(open: Set<string>) {
  try {
    window.sessionStorage?.setItem(OPEN_KEY, JSON.stringify([...open]));
  } catch {
    // No storage: the folds last as long as the window.
  }
}

/** Below this width the index becomes a drawer over the article. */
const NARROW = 640;

function useNarrow(): boolean {
  const [narrow, setNarrow] = useState(() => window.innerWidth < NARROW);
  useEffect(() => {
    const onResize = () => setNarrow(window.innerWidth < NARROW);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);
  return narrow;
}

export const StationWiki = () => {
  const { act, data } = useBackend<Data>();
  const index = data.index || [];
  const article = data.article;
  const tree = useMemo(() => buildTree(index), [index]);
  const titles = useMemo(
    () => new Map(index.map((row) => [row[0], row[1]] as [string, string])),
    [index],
  );
  const pathOf = useMemo(
    () => new Map(index.map((row) => [row[0], row[2]] as [string, string])),
    [index],
  );
  const [query, setQuery] = useState('');
  const [cursor, setCursor] = useState(0);
  const [open, setOpen] = useState<Set<string>>(loadOpen);
  const [history, setHistory] = useState<string[]>([]);
  const [pos, setPos] = useState(-1);
  /** A section landing page shown instead of the article (null: the article). */
  const [section, setSection] = useState<string | null>(null);
  const narrow = useNarrow();
  const [drawer, setDrawer] = useState(false);
  const pending = useRef<string | null>(null);
  const scroller = useRef<HTMLDivElement>(null);

  const requested = data.requested;
  // The server's article is the reader's: a page opened from outside joins the history.
  useEffect(() => {
    if (!requested) return;
    if (pending.current !== null) {
      if (pending.current === requested) pending.current = null;
      return;
    }
    if (history[pos] !== requested) {
      const next = [...history.slice(0, pos + 1), requested];
      setHistory(next);
      setPos(next.length - 1);
      setSection(null);
    }
  }, [requested]);

  const expand = (path: string) =>
    setOpen((prev) => {
      const next = new Set(prev);
      const parts = path.split('/');
      for (let i = 1; i <= parts.length; i++)
        next.add(parts.slice(0, i).join('/'));
      return next;
    });

  // The current article's sections open themselves.
  useEffect(() => {
    const path = pathOf.get(requested);
    if (path) expand(path);
  }, [requested, pathOf]);

  useEffect(() => saveOpen(open), [open]);

  // A new page starts at its top.
  useEffect(() => {
    scroller.current?.scrollTo?.(0, 0);
  }, [requested, section, article?.id]);

  const visit = (id: string, newPos: number, newHistory: string[]) => {
    pending.current = id;
    setHistory(newHistory);
    setPos(newPos);
    setSection(null);
    setDrawer(false);
    act('open', { id });
  };
  const go = (id: string) => {
    if (id === requested) {
      setSection(null);
      setDrawer(false);
      return;
    }
    const next = [...history.slice(0, pos + 1), id];
    visit(id, next.length - 1, next);
  };
  const back = () => {
    if (section !== null) setSection(null);
    else if (pos > 0) visit(history[pos - 1], pos - 1, history);
  };
  const forward = () =>
    pos < history.length - 1 && visit(history[pos + 1], pos + 1, history);
  const toggle = (key: string) =>
    setOpen((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  const openSection = (key: string) => {
    setSection(key);
    expand(key);
    setDrawer(false);
  };
  const ctx: Ctx = { titles, go };
  const results = useMemo(() => searchIndex(index, query), [index, query]);
  useEffect(() => setCursor(0), [query]);

  const onSearchKey = (e: React.KeyboardEvent) => {
    if (!results.length) return;
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setCursor((c) => Math.min(c + 1, results.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setCursor((c) => Math.max(c - 1, 0));
    }
  };

  const sectionNode = section !== null ? findNode(tree, section) : null;
  const factsAt = article && !sectionNode ? infoboxFacts(article) : -1;
  const hasInfobox =
    !!article &&
    !sectionNode &&
    (!!article.icon || !!article.swatch || factsAt >= 0);
  const bodyBlocks =
    article && factsAt >= 0
      ? article.blocks.filter((_, i) => i !== factsAt)
      : (article?.blocks ?? []);
  const crumbPath = sectionNode ? sectionNode.key : (article?.path ?? '');
  const accent = deptOf(crumbPath).color;
  const isHome = !sectionNode && article?.id === data.home;

  const sidebar = (
    <div className="StationWiki__sidebar">
      {narrow ? (
        <div className="StationWiki__drawerHead">
          <Icon name="book" mr={0.5} />
          Index
          <Button
            ml="auto"
            icon="xmark"
            tooltip="Close"
            onClick={() => setDrawer(false)}
          />
        </div>
      ) : null}
      <div className="StationWiki__search" onKeyDown={onSearchKey}>
        <Input
          fluid
          placeholder="Search the wiki..."
          value={query}
          onChange={setQuery}
          onEnter={() => {
            const row = results[cursor];
            if (row) go(row[0]);
          }}
          onEscape={() => setQuery('')}
        />
      </div>
      <div className="StationWiki__index">
        {query.trim() ? (
          <SearchResults
            results={results}
            query={query}
            cursor={cursor}
            current={requested}
            ctx={ctx}
          />
        ) : (
          <TreeNode
            node={tree}
            depth={-1}
            open={open}
            toggle={toggle}
            current={sectionNode ? null : requested}
            currentSection={section}
            go={go}
            openSection={openSection}
          />
        )}
      </div>
    </div>
  );

  return (
    <Window width={980} height={680} title="Station Wiki">
      <Window.Content>
        <div
          className={`StationWiki${narrow ? ' StationWiki--narrow' : ''}${drawer ? ' StationWiki--drawer' : ''}`}
        >
          {sidebar}
          <div className="StationWiki__main">
            <header
              className="StationWiki__header"
              style={{ borderBottomColor: accent }}
            >
              <div className="StationWiki__nav">
                {narrow ? (
                  <Button
                    icon={drawer ? 'xmark' : 'bars'}
                    tooltip="Index"
                    selected={drawer}
                    onClick={() => setDrawer(!drawer)}
                  />
                ) : null}
                <Button
                  icon="arrow-left"
                  tooltip="Back"
                  disabled={section === null && pos <= 0}
                  onClick={back}
                />
                <Button
                  icon="arrow-right"
                  tooltip="Forward"
                  disabled={pos >= history.length - 1}
                  onClick={forward}
                />
                <Breadcrumbs
                  path={crumbPath}
                  openSection={openSection}
                  goHome={() => go(data.home)}
                />
              </div>
              <h1 className="StationWiki__title">
                {sectionNode
                  ? sectionNode.name
                  : article
                    ? article.title
                    : 'No such article'}
                {sectionNode ? (
                  <span className="StationWiki__titleCount">
                    {sectionNode.count} article
                    {sectionNode.count === 1 ? '' : 's'}
                  </span>
                ) : null}
              </h1>
              {!sectionNode && article?.summary ? (
                <div className="StationWiki__summary">
                  <Inline text={article.summary} ctx={ctx} />
                </div>
              ) : null}
            </header>
            <div className="StationWiki__scroll" ref={scroller}>
              <div className="StationWiki__body">
                {sectionNode ? (
                  <SectionLanding
                    node={sectionNode}
                    ctx={ctx}
                    openSection={openSection}
                  />
                ) : article ? (
                  <>
                    {hasInfobox ? (
                      <Infobox
                        article={article}
                        facts={
                          factsAt >= 0
                            ? (
                                article.blocks[factsAt] as {
                                  rows: [string, string][];
                                }
                              ).rows
                            : null
                        }
                        ctx={ctx}
                        openSection={openSection}
                      />
                    ) : null}
                    <Blocks
                      blocks={bodyBlocks}
                      ctx={ctx}
                      articleId={article.id}
                    />
                    {isHome ? (
                      <DepartmentCards tree={tree} openSection={openSection} />
                    ) : (
                      <Related
                        article={article}
                        tree={tree}
                        ctx={ctx}
                        openSection={openSection}
                      />
                    )}
                  </>
                ) : (
                  <div className="StationWiki__callout StationWiki__callout--danger">
                    <Icon
                      name="circle-exclamation"
                      className="StationWiki__calloutIcon"
                    />
                    <div>
                      There is no article called "{requested}".{' '}
                      <Button onClick={() => go(data.home)}>Front page</Button>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </Window.Content>
    </Window>
  );
};
