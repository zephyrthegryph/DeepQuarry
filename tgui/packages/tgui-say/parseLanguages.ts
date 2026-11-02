/**
 * The say preview's reading of a message. It holds no rule data of its own: everything comes from the server
 * (code/content/tgui_input/say_modal/language_rules.dm). The logic follows find_valid_prefixes and parse_languages in
 * code/content/mob/say.dm, and code/tests/unit_tests/data/language_parse_cases.json runs over both.
 */
export type LanguageInfo = {
  /** Say, ask and exclaim verbs. */
  verbs: [string, string, string];
  whisperVerb: string;
  spoken: boolean;
  /** Takes the entire message (hivemind, sign, inaudible). */
  whole: boolean;
  /** Replaces the whole line (noise); never a switch past the message start. */
  innate: boolean;
  noHiss: boolean;
};

export type HissRules = {
  basic: Record<string, string[]>;
  /** Merged in on full mode only; null when autohiss is on basic. */
  extra: Record<string, string[]> | null;
  exempt: string[];
};

export type LanguageRules = {
  prefixes: string[];
  /** "Default", "Space", "Double Delimiter" or "Single Language". */
  mode: string;
  name: string;
  defaultLanguage: string;
  gibberish: string;
  noise: string;
  /** Typed key to language name. */
  keys: Record<string, string>;
  languages: Record<string, LanguageInfo>;
  /** The language list's order, for the Ctrl+number shortcuts. */
  order: string[];
  /** Delimiter to tag, in the order the server applies them. */
  markers: Record<string, string>;
  radioKeys: string[];
  autopunctuation: boolean;
  customVerbs: { say: string; ask: string; exclaim: string; whisper: string };
  hiss: HissRules | null;
};

export type Piece = { language: string; text: string };
export type Parsed = { pieces: Piece[]; whole: boolean };

const trim = (text: string) => text.replace(/^\s+|\s+$/g, '');

export type Switch = { language: string; start: number; textStart: number };

export function findSwitches(message: string, rules: LanguageRules): Switch[] {
  const found: Switch[] = [];
  const isPrefix = (char: string) => rules.prefixes.includes(char);
  for (let i = 0; i < message.length; i++) {
    if (i > 0) {
      if (rules.mode === 'Single Language') break;
      if (message[i - 1] !== ' ') continue;
    }
    if (!isPrefix(message[i])) continue;
    const codePoint = message.codePointAt(i + 1);
    if (codePoint === undefined || codePoint === 32) continue;
    const key = String.fromCodePoint(codePoint);
    let textStart = i + 1 + key.length;
    if (rules.mode === 'Space' && message[textStart] !== ' ') continue;
    if (rules.mode === 'Double Delimiter') {
      if (!isPrefix(message[textStart] ?? '')) continue;
      textStart++;
    }
    const language = rules.keys[key];
    const info = language ? rules.languages[language] : null;
    if (!info) continue;
    if (info.spoken) {
      if (i > 0 && info.innate) continue;
      found.push({ language, start: i, textStart });
    } else if (i === 0) {
      found.push({ language: rules.gibberish, start: i, textStart });
    }
  }
  if (!found.length || found[0].start !== 0) {
    found.unshift({ language: rules.defaultLanguage, start: 0, textStart: 0 });
  }
  return found;
}

function stripSwitches(message: string, rules: LanguageRules): string {
  const switches = findSwitches(message, rules);
  return switches
    .map((current, i) =>
      trim(message.slice(current.textStart, switches[i + 1]?.start)),
    )
    .filter((text) => text.length)
    .join(' ');
}

export function parseLanguages(message: string, rules: LanguageRules): Parsed {
  if (message[0] === '!' && message.length > 1) {
    return {
      whole: false,
      pieces: [
        {
          language: rules.noise,
          text: trim(stripSwitches(message.slice(1), rules)),
        },
      ],
    };
  }
  const switches = findSwitches(message, rules);
  for (const current of switches) {
    if (rules.languages[current.language]?.whole) {
      return {
        whole: true,
        pieces: [
          { language: current.language, text: stripSwitches(message, rules) },
        ],
      };
    }
  }
  const pieces: Piece[] = [];
  switches.forEach((current, i) => {
    const text = trim(message.slice(current.textStart, switches[i + 1]?.start));
    if (text.length) pieces.push({ language: current.language, text });
  });
  if (!pieces.length) pieces.push({ language: switches[0].language, text: '' });
  return { pieces, whole: false };
}

/** handle_autohiss, taking each map's first choice where the server picks at random. */
export function applyHiss(
  input: string,
  language: string,
  rules: LanguageRules,
): string {
  const hiss = rules.hiss;
  if (!hiss || rules.languages[language]?.noHiss) return input;
  if (hiss.exempt.includes(language)) return input;
  const map = { ...hiss.extra, ...hiss.basic };
  const lower = input.toLowerCase();
  const chars = Object.keys(map);
  let out = '';
  let at = 0;
  while (at < input.length) {
    let index = -1;
    let match = '';
    for (const char of chars) {
      const found = lower.indexOf(char, at);
      if (found !== -1 && (index === -1 || found < index)) {
        index = found;
        match = char;
      }
    }
    if (index === -1) break;
    out += input.slice(at, index);
    const replacement = map[match][0];
    if (input[index] === match.toUpperCase()) {
      const next = input.charCodeAt(index + 1);
      out +=
        next >= 65 && next <= 90
          ? replacement.toUpperCase()
          : replacement[0].toUpperCase() + replacement.slice(1);
    } else {
      out += replacement;
    }
    at = index + 1;
  }
  return out + input.slice(at);
}

export type Segment = { text: string; tags: string[] };
export type PreviewPiece = { language: string; segments: Segment[] };
export type Preview = {
  name: string;
  verb: string;
  whole: boolean;
  pieces: PreviewPiece[];
};

const SEPARATOR = '\u0000';
const escapeRegex = (char: string) =>
  char.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** encode_html_emphasis over the whole line, so a span can cross pieces as it does in chat. */
export function emphasize(texts: string[], rules: LanguageRules): Segment[][] {
  const joined = texts.join(SEPARATOR);
  const hidden = new Array<boolean>(joined.length).fill(false);
  const tags = joined.split('').map(() => [] as string[]);
  for (const delimiter of Object.keys(rules.markers)) {
    const quoted = escapeRegex(delimiter);
    const regex = new RegExp(`${quoted}([\\s\\S]+?)${quoted}`, 'g');
    for (const match of joined.matchAll(regex)) {
      const start = match.index;
      const end = start + match[0].length - 1;
      hidden[start] = true;
      hidden[end] = true;
      for (let i = start + 1; i < end; i++)
        tags[i].push(rules.markers[delimiter]);
    }
  }
  const result: Segment[][] = [[]];
  for (let i = 0; i < joined.length; i++) {
    if (joined[i] === SEPARATOR) {
      result.push([]);
      continue;
    }
    if (hidden[i]) continue;
    const segments = result[result.length - 1];
    const last = segments[segments.length - 1];
    if (last && last.tags.join() === tags[i].join()) {
      last.text += joined[i];
    } else {
      segments.push({ text: joined[i], tags: tags[i] });
    }
  }
  return result;
}

/** The radio key parse_message_mode would consume, and what that leaves. */
export function stripChannel(
  message: string,
  rules: LanguageRules,
): { text: string; whisper: boolean } {
  if (message[0] === ';') return { text: message.slice(1), whisper: false };
  const key = message.slice(0, 2);
  if (rules.radioKeys.includes(key)) {
    return { text: message.slice(2), whisper: key[1].toLowerCase() === 'w' };
  }
  return { text: message, whisper: false };
}

/**
 * What the speaker will see, or null for a message with nothing to show:
 * one piece in the preferred language, no formatting, nothing hissed.
 */
export function buildPreview(
  entry: string,
  channel: string,
  rules: LanguageRules,
): Preview | null {
  if (!['Say', 'Radio', 'Whis'].includes(channel)) return null;
  if (!trim(entry) || entry[0] === '*' || entry[0] === '^') return null;
  const stripped = stripChannel(entry, rules);
  const whisper = channel === 'Whis' || stripped.whisper;
  let message = stripped.text.replace(/^\s+/, '');
  if (rules.autopunctuation && /[a-z0-9]$/i.test(message)) message += '.';

  const parsed = parseLanguages(message, rules);
  const pieces = parsed.pieces.filter((piece) => piece.text.length);
  if (!pieces.length) return null;
  const texts = pieces.map((piece) =>
    parsed.whole ? piece.text : applyHiss(piece.text, piece.language, rules),
  );
  texts[0] = texts[0][0].toUpperCase() + texts[0].slice(1);
  const segments = emphasize(texts, rules);

  const changed =
    pieces.length > 1 ||
    parsed.whole ||
    pieces[0].language !== rules.defaultLanguage ||
    segments[0].some((segment) => segment.tags.length) ||
    applyHiss(pieces[0].text, pieces[0].language, rules) !== pieces[0].text;
  if (!changed) return null;

  const first = rules.languages[pieces[0].language];
  const ending = message[message.length - 1];
  const custom = rules.customVerbs;
  let verb =
    first?.verbs[ending === '!' ? 2 : ending === '?' ? 1 : 0] ?? 'says';
  if (whisper) {
    verb = custom.whisper || first?.whisperVerb || `${verb} quietly`;
  } else if (ending === '!' && custom.exclaim) {
    verb = custom.exclaim;
  } else if (ending === '?' && custom.ask) {
    verb = custom.ask;
  } else if (custom.say) {
    verb = custom.say;
  }

  return {
    name: rules.name,
    verb,
    whole: parsed.whole,
    pieces: pieces.map((piece, i) => ({
      language: piece.language,
      segments: segments[i],
    })),
  };
}
