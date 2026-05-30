// HTML renderer for legacy server-generated content.
//
// Many SS13 features store player-written or lore-authored bodies as
// HTML strings (paper info, book contents, newspaper articles, codex
// lore, stamps). Instead of dropping these into dangerouslySetInnerHTML
// we parse with the browser's DOMParser and walk the result, emitting
// real React elements. This gives us:
//   - structured rendering (no innerHTML; React owns the tree)
//   - byond://?src=...&action=Y links rewritten into act() callbacks
//     so navigation and field-edits stay inside the TGUI message loop
//   - an allow-list of safe tags; unknown tags render as plain text
//
// Pencode (paper, books, newspaper) is already parsepencode'd into HTML
// upstream, so this same renderer handles all of them.

import type { ElementType, ReactNode } from 'react';
import { Box, Button } from 'tgui-core/components';
import type { ActFn } from './PanelTypes';

type Props = {
  html: string;
  // When set, byond://?src=...action=foo&bar=baz links route to
  // onLinkAction("foo", {bar: "baz"}) instead of triggering BYOND.
  onLinkAction?: (action: string, params: Record<string, string>) => void;
  // Render an <span class="paper_field"> as this. Falls back to "_____".
  renderField?: (id: number, content: string) => ReactNode;
  // Top-level act() — used as a default for unknown link actions when
  // no explicit onLinkAction handler is supplied.
  act?: ActFn;
  // When set, ALL byond://... <a> clicks send the entire querystring to
  // the supplied act/onLinkAction as a single "forward_topic" action.
  // Used by AdminLogViewer to relay clicks into a host datum's Topic().
  forwardTopic?: boolean;
};

const ALLOWED_INLINE = new Set([
  'b',
  'strong',
  'i',
  'em',
  'u',
  'small',
  'big',
  'sub',
  'sup',
  'span',
  'font',
  'tt',
  'code',
]);

const ALLOWED_BLOCK = new Set([
  'p',
  'div',
  'center',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'pre',
  'ul',
  'ol',
  'li',
  'hr',
  'br',
  'table',
  'thead',
  'tbody',
  'tr',
  'td',
  'th',
]);

const parseByondLink = (
  href: string,
): { action: string; params: Record<string, string> } | null => {
  // Accepts ?src=...&action=X&p=1 and ?...action=X formats.
  let qs = href;
  if (qs.startsWith('byond://')) qs = qs.slice('byond://'.length);
  const q = qs.indexOf('?');
  if (q >= 0) qs = qs.slice(q + 1);
  const params: Record<string, string> = {};
  for (const part of qs.split('&')) {
    if (!part) continue;
    const eq = part.indexOf('=');
    if (eq < 0) {
      params[decodeURIComponent(part)] = '';
    } else {
      params[decodeURIComponent(part.slice(0, eq))] = decodeURIComponent(
        part.slice(eq + 1),
      );
    }
  }
  // Topic-style links: the action key is whichever non-src key has a
  // truthy value, and the rest are its params. SS13 hrefs typically use
  // the action as a named param (e.g. write=end, target=\ref[X]).
  for (const key of Object.keys(params)) {
    if (key === 'src') continue;
    return {
      action: key,
      params: { ...params, [key]: params[key] },
    };
  }
  return null;
};

const renderNode = (node: ChildNode, key: number, props: Props): ReactNode => {
  if (node.nodeType === Node.TEXT_NODE) {
    return node.textContent ?? '';
  }
  if (node.nodeType !== Node.ELEMENT_NODE) return null;
  const el = node as Element;
  const tag = el.tagName.toLowerCase();
  const children = Array.from(el.childNodes).map((c, i) =>
    renderNode(c, i, props),
  );

  if (tag === 'br') return <br key={key} />;
  if (tag === 'hr') return <hr key={key} />;
  if (tag === 'img') {
    const src = el.getAttribute('src');
    if (!src) return null;
    return <img key={key} src={src} alt="" />;
  }

  if (tag === 'a') {
    const href = el.getAttribute('href') ?? '';
    if (href.startsWith('byond://')) {
      if (props.forwardTopic && (props.onLinkAction || props.act)) {
        // Forward the entire querystring to the host's Topic() via a
        // single named action so the host can route it natively.
        let qs = href.slice('byond://'.length);
        const q = qs.indexOf('?');
        if (q >= 0) qs = qs.slice(q + 1);
        const onClick = () => {
          if (props.onLinkAction) {
            props.onLinkAction('forward_topic', { href: qs });
          } else if (props.act) {
            props.act('forward_topic', { href: qs });
          }
        };
        return (
          <Button key={key} compact onClick={onClick}>
            {children}
          </Button>
        );
      }
      const parsed = parseByondLink(href);
      if (parsed && (props.onLinkAction || props.act)) {
        const onClick = () => {
          if (props.onLinkAction) {
            props.onLinkAction(parsed.action, parsed.params);
          } else if (props.act) {
            props.act(parsed.action, parsed.params);
          }
        };
        return (
          <Button key={key} compact onClick={onClick}>
            {children}
          </Button>
        );
      }
    }
    // External links are rendered as plain text; TGUI can't open them.
    return (
      <Box inline key={key}>
        {children}
      </Box>
    );
  }

  if (tag === 'span') {
    const cls = el.getAttribute('class') ?? '';
    if (cls.includes('paper_field')) {
      const id = parseInt(el.getAttribute('data-field-id') ?? '0', 10);
      const text = el.textContent ?? '';
      if (props.renderField) {
        return <span key={key}>{props.renderField(id, text)}</span>;
      }
      return (
        <Box inline italic key={key}>
          {text || '_______'}
        </Box>
      );
    }
    // Class-based color spans we expect (span_red, span_blue, etc.) —
    // best-effort color extraction.
    if (cls.startsWith('span_')) {
      const color = cls.slice('span_'.length);
      return (
        <Box inline color={color} key={key}>
          {children}
        </Box>
      );
    }
    return <span key={key}>{children}</span>;
  }

  if (tag === 'font') {
    const color = el.getAttribute('color') || undefined;
    const face = el.getAttribute('face') || undefined;
    const size = el.getAttribute('size') || undefined;
    return (
      <span
        key={key}
        style={{
          color,
          fontFamily: face,
          fontSize:
            size === '1' ? '0.85em' : size === '4' ? '1.4em' : undefined,
        }}
      >
        {children}
      </span>
    );
  }

  if (ALLOWED_INLINE.has(tag) || ALLOWED_BLOCK.has(tag)) {
    // Dynamic JSX element — typed as ElementType so TS doesn't try to
    // resolve every possible HTML tag against JSX.IntrinsicElements.
    const Tag = tag as ElementType;
    return <Tag key={key}>{children}</Tag>;
  }

  // Unknown tag: render children as fallback so we don't lose content.
  return <span key={key}>{children}</span>;
};

export const HtmlRenderer = (props: Props) => {
  if (!props.html) return null;
  // Wrap in a host node so DOMParser gives us a single fragment with all
  // top-level children accessible.
  const doc = new DOMParser().parseFromString(
    `<div>${props.html}</div>`,
    'text/html',
  );
  const root = doc.body.firstChild as Element | null;
  if (!root) return null;
  return (
    <>{Array.from(root.childNodes).map((c, i) => renderNode(c, i, props))}</>
  );
};
