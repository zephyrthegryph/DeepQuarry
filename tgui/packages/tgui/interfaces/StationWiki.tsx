/**
 * The station wiki (code/content/wiki/): the index on the left (sections that
 * fold open and shut, and a search), the article on the right. The index
 * comes once per open as static data; the server sends only the article the
 * reader is on. Back and forward are this window's own history of ids; a page
 * opened from outside (a reference book) lands in it.
 *
 * Article bodies are blocks (wiki.dm's header): paragraphs, headings, lists,
 * notes, labelled facts, link rows, tables and tabs. Any text may carry
 * inline links, [[id]] or [[id|label]], and **bold**.
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
  Icon,
  Input,
  LabeledList,
  Section,
  Stack,
  Table,
  Tooltip,
} from 'tgui-core/components';

/** One index row: id, title, path ("Medical/Conditions/Cardiac"), summary. */
type IndexRow = [string, string, string, string];

type Link = {
  id: string | null;
  name: string;
  note?: string | null;
  tone?: string | null;
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

type Node = {
  name: string;
  key: string;
  children: Map<string, Node>;
  articles: IndexRow[];
};

export function buildTree(index: IndexRow[]): Node {
  const root: Node = { name: '', key: '', children: new Map(), articles: [] };
  for (const row of index) {
    let node = root;
    for (const part of (row[2] || 'Uncategorised').split('/')) {
      const key = node.key ? `${node.key}/${part}` : part;
      let child = node.children.get(part);
      if (!child) {
        child = { name: part, key, children: new Map(), articles: [] };
        node.children.set(part, child);
      }
      node = child;
    }
    node.articles.push(row);
  }
  return root;
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
              <Box as="span" color="bad">
                {label}
              </Box>
            </Tooltip>
          );
        return (
          <Box
            key={i}
            as="a"
            className="StationWiki__link"
            onClick={() => ctx.go(part.id)}
          >
            {label}
          </Box>
        );
      })}
    </>
  );
}

function LinkRow(props: { block: { t: string; items: Link[] }; ctx: Ctx }) {
  const { block, ctx } = props;
  return (
    <>
      <Box className="StationWiki__rowLabel">
        <Inline text={block.t} ctx={ctx} />
      </Box>
      <Box className="StationWiki__rowItems">
        {block.items.map((item, i) => (
          <Box key={`${item.id}-${i}`} inline className="StationWiki__chip">
            {item.id && ctx.titles.has(item.id) ? (
              <Button
                compact
                color={item.tone || 'transparent'}
                onClick={() => ctx.go(item.id as string)}
              >
                {item.name}
              </Button>
            ) : (
              <Box inline px={0.5}>
                {item.name}
              </Box>
            )}
            {item.note ? (
              <Box inline color="label" fontSize="0.85em" ml={0.5}>
                <Inline text={item.note} ctx={ctx} />
              </Box>
            ) : null}
          </Box>
        ))}
      </Box>
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
    <Box mt={1}>
      <Tabs
        tabs={props.tabs.map((tab, i) => ({
          id: `${i}`,
          label: tab.name,
          selected: i === selected,
        }))}
        onSelect={(id) => setSelected(Number(id))}
      />
      <Box mt={1}>
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

function Blocks(props: { blocks: Block[]; ctx: Ctx; articleId: string }) {
  const { ctx } = props;
  const out: ReactNode[] = [];
  let rows: ReactNode[] = [];
  // Consecutive link rows share one grid so their labels line up.
  const flush = (key: string) => {
    if (rows.length) {
      out.push(
        <Box key={`grid-${key}`} className="StationWiki__grid">
          {rows}
        </Box>,
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
          <Box key={i} className="StationWiki__p">
            <Inline text={block.t} ctx={ctx} />
          </Box>,
        );
        break;
      case 'h':
        out.push(
          <Box key={i} className="StationWiki__h">
            <Inline text={block.t} ctx={ctx} />
          </Box>,
        );
        break;
      case 'note':
        out.push(
          <Box
            key={i}
            className="StationWiki__note"
            color={
              block.tone && block.tone !== 'label' ? block.tone : undefined
            }
          >
            <Inline text={block.t} ctx={ctx} />
          </Box>,
        );
        break;
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
        out.push(
          <Box key={i} mb={1}>
            <LabeledList>
              {block.rows.map(([label, text]) => (
                <LabeledList.Item key={label} label={label}>
                  <Inline text={text} ctx={ctx} />
                </LabeledList.Item>
              ))}
            </LabeledList>
          </Box>,
        );
        break;
      case 'table':
        out.push(
          <Table key={i} className="StationWiki__table">
            <Table.Row header>
              {block.head.map((cell) => (
                <Table.Cell key={cell}>{cell}</Table.Cell>
              ))}
            </Table.Row>
            {block.rows.map((row, j) => (
              <Table.Row key={j}>
                {row.map((cell, c) => (
                  <Table.Cell key={c}>
                    <Inline text={cell} ctx={ctx} />
                  </Table.Cell>
                ))}
              </Table.Row>
            ))}
          </Table>,
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

function TreeNode(props: {
  node: Node;
  depth: number;
  open: Set<string>;
  toggle: (key: string) => void;
  current: string | null;
  go: (id: string) => void;
}) {
  const { node, depth, open, toggle, current, go } = props;
  const children = [...node.children.values()].sort((a, b) =>
    compareSections(a.name, b.name),
  );
  const articles = [...node.articles].sort((a, b) => a[1].localeCompare(b[1]));
  const body = (
    <>
      {articles.map((row) => (
        <Button
          key={row[0]}
          fluid
          className="StationWiki__entry"
          color={row[0] === current ? 'green' : 'transparent'}
          onClick={() => go(row[0])}
          style={{ paddingLeft: `${0.5 + depth * 0.75}em` }}
        >
          {row[1]}
        </Button>
      ))}
      {children.map((child) => (
        <TreeNode
          key={child.key}
          node={child}
          depth={depth + 1}
          open={open}
          toggle={toggle}
          current={current}
          go={go}
        />
      ))}
    </>
  );
  if (depth < 0) return body;
  const isOpen = open.has(node.key);
  return (
    <Box>
      <Button
        fluid
        color="transparent"
        className="StationWiki__section"
        onClick={() => toggle(node.key)}
        style={{ paddingLeft: `${0.25 + depth * 0.75}em` }}
      >
        <Icon name={isOpen ? 'chevron-down' : 'chevron-right'} mr={0.5} />
        {node.name}
      </Button>
      {isOpen ? body : null}
    </Box>
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
  const [open, setOpen] = useState<Set<string>>(new Set());
  const [history, setHistory] = useState<string[]>([]);
  const [pos, setPos] = useState(-1);
  const pending = useRef<string | null>(null);

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
    }
  }, [requested]);

  // The current article's sections open themselves.
  useEffect(() => {
    const path = pathOf.get(requested);
    if (!path) return;
    setOpen((prev) => {
      const next = new Set(prev);
      const parts = path.split('/');
      for (let i = 1; i <= parts.length; i++)
        next.add(parts.slice(0, i).join('/'));
      return next;
    });
  }, [requested, pathOf]);

  const visit = (id: string, newPos: number, newHistory: string[]) => {
    pending.current = id;
    setHistory(newHistory);
    setPos(newPos);
    act('open', { id });
  };
  const go = (id: string) => {
    if (id === requested) return;
    const next = [...history.slice(0, pos + 1), id];
    visit(id, next.length - 1, next);
  };
  const back = () => pos > 0 && visit(history[pos - 1], pos - 1, history);
  const forward = () =>
    pos < history.length - 1 && visit(history[pos + 1], pos + 1, history);
  const toggle = (key: string) =>
    setOpen((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  const ctx: Ctx = { titles, go };
  const results = useMemo(() => searchIndex(index, query), [index, query]);

  return (
    <Window width={900} height={640} title="Station Wiki">
      <Window.Content>
        <Stack fill>
          <Stack.Item basis="32%">
            <Section
              fill
              scrollable
              title={
                <Input
                  fluid
                  placeholder="Search the wiki..."
                  value={query}
                  onChange={setQuery}
                />
              }
            >
              {query.trim() ? (
                results.length ? (
                  results.map((row) => (
                    <Button
                      key={row[0]}
                      fluid
                      className="StationWiki__entry"
                      color={row[0] === requested ? 'green' : 'transparent'}
                      onClick={() => go(row[0])}
                    >
                      {row[1]}
                      <Box inline color="label" fontSize="0.8em" ml={0.5}>
                        {row[2]}
                      </Box>
                    </Button>
                  ))
                ) : (
                  <Box color="label">Nothing matches.</Box>
                )
              ) : (
                <TreeNode
                  node={tree}
                  depth={-1}
                  open={open}
                  toggle={toggle}
                  current={requested}
                  go={go}
                />
              )}
            </Section>
          </Stack.Item>
          <Stack.Item grow basis={0}>
            <Section
              fill
              scrollable
              title={article ? article.title : 'No such article'}
              buttons={
                <>
                  <Button
                    icon="arrow-left"
                    tooltip="Back"
                    disabled={pos <= 0}
                    onClick={back}
                  />
                  <Button
                    icon="arrow-right"
                    tooltip="Forward"
                    disabled={pos >= history.length - 1}
                    onClick={forward}
                  />
                  <Button
                    icon="home"
                    tooltip="Front page"
                    onClick={() => go(data.home)}
                  />
                </>
              }
            >
              {article ? (
                <>
                  <Box color="label" fontSize="0.85em" mb={1}>
                    {article.path.split('/').join(' / ')}
                  </Box>
                  {article.summary ? (
                    <Box italic color="label" mb={1}>
                      {article.summary}
                    </Box>
                  ) : null}
                  <Blocks
                    blocks={article.blocks}
                    ctx={ctx}
                    articleId={article.id}
                  />
                </>
              ) : (
                <Box color="bad">
                  There is no article called "{requested}".{' '}
                  <Button onClick={() => go(data.home)}>Front page</Button>
                </Box>
              )}
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
