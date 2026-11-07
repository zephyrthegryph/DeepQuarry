/** The say box's text shortcuts, as pure edits. Markers and keys are the game's own: the server's formatting markers and language keys. */
import {
  findSwitches,
  type LanguageRules,
  stripChannel,
} from './parseLanguages';

export type TextEdit = { value: string; start: number; end: number };

/** The emphasis marker each Ctrl shortcut toggles (Ctrl+B bold, Ctrl+I italic, Ctrl+U underline). */
export const SHORTCUT_MARKERS: Record<string, string> = {
  b: '+',
  i: '|',
  u: '_',
};

/** Ctrl+B/I/U: wrap or unwrap the selection, or at the cursor open a pair, step out of it, or drop an empty one. */
export function toggleMarker(
  value: string,
  start: number,
  end: number,
  marker: string,
): TextEdit {
  const size = marker.length;
  if (start !== end) {
    const selected = value.slice(start, end);
    if (
      selected.length >= size * 2 &&
      selected.startsWith(marker) &&
      selected.endsWith(marker)
    ) {
      const inner = selected.slice(size, -size);
      return {
        value: value.slice(0, start) + inner + value.slice(end),
        start,
        end: start + inner.length,
      };
    }
    if (
      value.slice(start - size, start) === marker &&
      value.slice(end, end + size) === marker
    ) {
      return {
        value:
          value.slice(0, start - size) + selected + value.slice(end + size),
        start: start - size,
        end: end - size,
      };
    }
    return {
      value: `${value.slice(0, start)}${marker}${selected}${marker}${value.slice(end)}`,
      start: start + size,
      end: end + size,
    };
  }
  const before = value.slice(0, start);
  const inside = before.split(marker).length % 2 === 0;
  if (inside) {
    if (value.slice(start, start + size) === marker) {
      if (before.endsWith(marker)) {
        // An empty pair: pressing again takes it back.
        return {
          value: value.slice(0, start - size) + value.slice(start + size),
          start: start - size,
          end: start - size,
        };
      }
      return { value, start: start + size, end: start + size };
    }
    const at = start + size;
    return {
      value: before + marker + value.slice(start),
      start: at,
      end: at,
    };
  }
  const at = start + size;
  return {
    value: `${before}${marker}${marker}${value.slice(start)}`,
    start: at,
    end: at,
  };
}

/** The prefix typed for a language: the first the server lists for it. */
function keyFor(language: string, rules: LanguageRules): string | undefined {
  return Object.keys(rules.keys).find((key) => rules.keys[key] === language);
}

/** What selects a language in text, trailing separator included, per the speaker's mode. */
function tokenFor(language: string, rules: LanguageRules): string | null {
  const prefix = keyFor(language, rules);
  if (!prefix) return null;
  return rules.mode === 'Double Delimiter'
    ? `${prefix}${prefix[0]}`
    : `${prefix} `;
}

/** Where the message proper starts: past a radio key, as the server reads it. */
function messageStart(value: string, rules: LanguageRules): number {
  const { text } = stripChannel(value, rules);
  return value.length - text.replace(/^\s+/, '').length;
}

type Located = {
  language: string;
  /** The switch that sets it, or null for the unkeyed start. */
  tokenStart: number | null;
  tokenEnd: number;
};

/** A switch's text starts after its key; the one space typed after the key belongs to the switch. */
function tokenEnd(value: string, textStart: number): number {
  return value[textStart] === ' ' ? textStart + 1 : textStart;
}

function locate(value: string, at: number, rules: LanguageRules): Located {
  const base = messageStart(value, rules);
  const switches = findSwitches(value.slice(base), rules);
  let current = switches[0];
  for (const candidate of switches) {
    if (candidate.start + base < at) current = candidate;
  }
  // A cursor right after a token counts as inside that language.
  for (const candidate of switches) {
    if (candidate.textStart + base <= at) current = candidate;
  }
  const keyed = current.textStart !== 0;
  return {
    language: current.language,
    tokenStart: keyed ? current.start + base : null,
    tokenEnd: tokenEnd(value, current.textStart + base),
  };
}

/** Replaces a range and keeps a key at a word start: it needs a space before it unless it opens the message. */
function placeToken(
  value: string,
  at: number,
  token: string,
  base: number,
): { value: string; after: number } {
  const needsSpace = at > base && value[at - 1] !== ' ';
  const text = (needsSpace ? ' ' : '') + token;
  return {
    value: value.slice(0, at) + text + value.slice(at),
    after: at + text.length,
  };
}

/** Ctrl+number: the nth language in the server's list, for the selection or from the cursor on; again returns to the preferred language. */
export function toggleLanguage(
  value: string,
  start: number,
  end: number,
  index: number,
  rules: LanguageRules,
): TextEdit | null {
  const target = rules.order[index - 1];
  if (!target) return null;
  const preferred = rules.defaultLanguage;
  const base = messageStart(value, rules);
  const here = locate(value, start, rules);

  if (rules.mode === 'Single Language') {
    // Only the message start can hold a key: switch the whole message.
    const head = locate(value, base, rules);
    const headEnd = head.tokenStart === null ? base : head.tokenEnd;
    const next = head.language === target ? preferred : target;
    const token = next === preferred ? '' : tokenFor(next, rules);
    if (token === null) return null;
    const moved = token.length - (headEnd - base);
    return {
      value: value.slice(0, base) + token + value.slice(headEnd),
      start: Math.max(start + moved, base + token.length),
      end: Math.max(end + moved, base + token.length),
    };
  }

  if (start !== end) {
    const directly = here.tokenStart !== null && here.tokenEnd === start;
    if (here.language === target && directly) {
      // Already this language: take the switch off and any switch closing it.
      let tail = value.slice(end);
      const closing = findSwitches(value.slice(base), rules).find(
        (candidate) =>
          candidate.start + base === end + (tail[0] === ' ' ? 1 : 0),
      );
      if (closing) {
        tail = value.slice(closing.textStart + base);
        if (tail.length && tail[0] !== ' ' && value[end] === ' ') {
          tail = ` ${tail}`;
        }
      }
      const head = value.slice(0, here.tokenStart as number);
      const selected = value.slice(start, end);
      return {
        value: head + selected + tail,
        start: head.length,
        end: head.length + selected.length,
      };
    }
    const opening = tokenFor(target, rules);
    const closing = tokenFor(here.language, rules);
    if (!opening) return null;
    const open = placeToken(value, start, opening, base);
    const moved = open.after - start;
    let result = open.value;
    const closeAt = end + moved;
    if (closing && closeAt < result.length) {
      // The text after the selection stays in the language it was in.
      const tail = result.slice(closeAt).replace(/^ /, '');
      result = `${result.slice(0, closeAt)} ${closing}${tail}`;
    }
    return { value: result, start: open.after, end: closeAt };
  }

  const next = here.language === target ? preferred : target;
  const justTyped = here.tokenStart !== null && here.tokenEnd === start;
  if (justTyped) {
    // A switch with no text yet is replaced, so presses never stack up.
    const tokenStart = here.tokenStart as number;
    const stripped = value.slice(0, tokenStart) + value.slice(start);
    const previous = locate(stripped, tokenStart, rules).language;
    if (previous === next) {
      return { value: stripped, start: tokenStart, end: tokenStart };
    }
    const token = tokenFor(next, rules);
    if (!token) return null;
    const placed = placeToken(stripped, tokenStart, token, base);
    return { value: placed.value, start: placed.after, end: placed.after };
  }
  const token = tokenFor(next, rules);
  if (!token) return null;
  const placed = placeToken(value, start, token, base);
  return { value: placed.value, start: placed.after, end: placed.after };
}

/** The indicator's text at the cursor, or null when nothing is active. */
export function activeAt(
  value: string,
  caret: number,
  rules: LanguageRules | null,
): string | null {
  const parts: string[] = [];
  if (rules) {
    const { language } = locate(value, caret, rules);
    if (language && language !== rules.defaultLanguage) parts.push(language);
  }
  const before = value.slice(0, caret);
  const markers = rules?.markers ?? { '|': 'i', '+': 'b', _: 'u' };
  for (const marker of Object.keys(markers)) {
    if (before.split(marker).length % 2 === 0) parts.push(markers[marker]);
  }
  return parts.length ? parts.join(' ') : null;
}
