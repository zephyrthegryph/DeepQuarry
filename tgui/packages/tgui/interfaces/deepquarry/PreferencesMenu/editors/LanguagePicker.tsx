// DQAdd — Language picker. One list of every language this character can have: known ones in green with their
// prefix, typed to speak it, and a button to make one the default. Languages it can't take aren't listed. A key another known language holds is refused here and again on the server.

import { useEffect, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Label } from 'tgui/components/Label';
import {
  Box,
  Button,
  Input,
  Tooltip,
} from 'tgui-core/components';
import type { PrefEditorLanguageStatic } from '../../../generated/_schemas';
import type { EditorProps } from './index';

type LangMeta = PrefEditorLanguageStatic['all_languages'][string];

type Act = ReturnType<typeof useBackend>['act'];

const send = (act: Act, action: string, params: Record<string, unknown>) =>
  act('dq_editor_action', { editor: 'language', action, params });

/// Why `key` (a whole prefix) cannot speak `language`, or null when it can: the rule of language_prefix_problem and language_key_problem.
export const languageKeyProblem = (
  key: string,
  language: string,
  keys: Record<string, string>,
): string | null => {
  const size = [...key].length;
  if (size < 2 || size > 4) return '2 to 4 characters.';
  if (key.includes(' ')) return 'No spaces.';
  if (/^[A-Za-z0-9;:.!*^+|_<>&"']/.test(key)) {
    return `Can't start with ${key[0]}.`;
  }
  for (const [other, held] of Object.entries(keys)) {
    if (other !== language && held === key) return `Already speaks ${other}.`;
  }
  return null;
};

/// The languages to list: unrestricted, pickable by this character (or already picked); picked ones first.
export const filterLanguages = (
  entries: [string, LangMeta][],
  pickable: Set<string> | null,
  selected: Set<string>,
): [string, LangMeta][] =>
  entries
    .filter(
      ([key, meta]) =>
        selected.has(key) ||
        (!meta.restricted && (!pickable || pickable.has(key))),
    )
    .sort((x, y) => {
      const xs = selected.has(x[0]) ? 0 : 1;
      const ys = selected.has(y[0]) ? 0 : 1;
      return xs - ys || x[1].name.localeCompare(y[1].name);
    });

export const LanguagePicker = ({
  data: d,
  staticData: s,
}: EditorProps<'language'>) => {
  const { act } = useBackend();

  const all = s?.all_languages ?? {};
  const selected = new Set(d.alternate_languages ?? []);
  const known = new Set(d.known_languages ?? []);
  const max = d.max_alternate_languages ?? 0;
  const room = Math.max(0, max - selected.size);
  const keys = d.language_keys ?? {};

  // The server names the languages this character may actually pick; anything else (restricted, whitelisted for someone
  // else) is not listed at all. Selected ones come first, then the rest alphabetically; the search narrows both.
  const pickable = d.pickable_languages ? new Set(d.pickable_languages) : null;
  const sortedLanguageEntries = filterLanguages(
    Object.entries(all),
    pickable,
    new Set([...selected, ...known]),
  );
  return (
    <Box>
      <Box
        mb={1}
        style={{
          display: 'flex',
          alignItems: 'flex-start',
          justifyContent: 'space-between',
          gap: '0.75em',
        }}
      >
        <Label fontSize="0.85em" style={{ minWidth: 0 }}>
          Pick up to{' '}
          <Box inline bold color="white">
            {max}
          </Box>{' '}
          alternate languages your character knows on top of their species
          default. Green languages are known. To speak another in chat, type
          its prefix.
        </Label>
        <Box
          style={{
            flex: '0 0 auto',
            padding: '0.167em 0.667em',
            borderRadius: '0.833em',
            backgroundColor:
              room === 0 ? 'rgba(231,76,60,0.2)' : 'rgba(255,255,255,0.06)',
            color: room === 0 ? '#E74C3C' : '#fff',
            fontWeight: 'bold',
            fontSize: '0.85em',
            whiteSpace: 'nowrap',
          }}
        >
          {selected.size} / {max} picked
        </Box>
      </Box>
          {sortedLanguageEntries.length === 0 && (
            <Label italic>No language to pick.</Label>
          )}
          <Box
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 17em), 1fr))',
              gap: '0.4em',
              alignItems: 'start',
            }}
          >
            {sortedLanguageEntries.map(([key, meta]) => (
              <LanguageTile
                key={key}
                languageKey={key}
                meta={meta}
                selected={selected.has(key)}
                known={known.has(key)}
                preferred={d.preferred_language === key}
                roomLeft={room}
                keys={keys}
                act={act}
              />
            ))}
          </Box>
    </Box>
  );
};

// ─── Single language tile ─────────────────────────────────────────────────────────

/// One language as a tile: the name toggles it (the language's description is the tooltip); a known one also shows the
/// prefix that speaks it and the button that makes it the default.
const LanguageTile = ({
  languageKey,
  meta,
  selected,
  known,
  preferred,
  roomLeft,
  keys,
  act,
}: {
  languageKey: string;
  meta: LangMeta;
  selected: boolean;
  known: boolean;
  preferred: boolean;
  roomLeft: number;
  keys: Record<string, string>;
  act: Act;
}) => {
  const canAdd = !selected && !known && roomLeft > 0;
  const toggles = selected || canAdd;
  return (
    <Box
      p={0.4}
      style={{
        minWidth: 0,
        borderRadius: '0.333em',
        background: known ? 'rgba(46,204,113,0.1)' : 'rgba(255,255,255,0.03)',
        border: known
          ? '1px solid rgba(46,204,113,0.5)'
          : '1px solid rgba(255,255,255,0.06)',
      }}
    >
      <Tooltip content={meta.desc || meta.name}>
        <Button
          fluid
          textAlign="center"
          color={known ? 'good' : 'default'}
          selected={selected}
          style={{
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
            cursor: toggles ? 'pointer' : 'default',
            opacity: toggles || known ? 1 : 0.55,
          }}
          onClick={() => {
            if (selected) {
              send(act, 'remove_language', { language: languageKey });
            } else if (canAdd) {
              send(act, 'add_language', { language: languageKey });
            }
          }}
        >
          {meta.name}
        </Button>
      </Tooltip>
      {known && (
        <Box
          mt={0.4}
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: '0.3em',
            flexWrap: 'nowrap',
          }}
        >
          <LanguageKeyInput
            languageKey={languageKey}
            defaultKey={meta.default_key ?? ''}
            keys={keys}
            act={act}
          />
          <Button
            compact
            selected={preferred}
            tooltip={
              preferred ? 'Spoken by default' : 'Speak this language by default'
            }
            onClick={() =>
              send(act, 'set_preferred', { language: languageKey })
            }
          >
            {preferred ? 'Default' : 'Set default'}
          </Button>
        </Box>
      )}
    </Box>
  );
};

/// The key that speaks a language: typed in place, sent when valid, refused with the reason beside it.
const LanguageKeyInput = ({
  languageKey,
  defaultKey,
  keys,
  act,
}: {
  languageKey: string;
  defaultKey: string;
  keys: Record<string, string>;
  act: Act;
}) => {
  const current = keys[languageKey] ?? '';
  const [draft, setDraft] = useState(current);
  const [problem, setProblem] = useState<string | null>(null);
  useEffect(() => {
    setDraft(current);
    setProblem(null);
  }, [current]);
  const commit = (value: string) => {
    if (value === current) {
      setProblem(null);
      return;
    }
    if (value === '') {
      send(act, 'reset_key', { language: languageKey });
      return;
    }
    const why = languageKeyProblem(value, languageKey, keys);
    setProblem(why);
    if (!why) send(act, 'set_key', { language: languageKey, key: value });
  };
  return (
    <Box style={{ minWidth: 0 }}>
      <Box
        style={{
          display: 'flex',
          alignItems: 'center',
          flexWrap: 'nowrap',
        }}
      >
      <Label inline mr={0.25}>
        Prefix
      </Label>
      <Input
        width="3.5em"
        maxLength={4}
        value={draft}
        onChange={setDraft}
        onBlur={() => commit(draft)}
        onEnter={() => commit(draft)}
      />
      {current !== defaultKey && !!defaultKey && (
        <Button
          ml={0.25}
          compact
          icon="rotate-left"
          tooltip={`Back to its own prefix (${defaultKey})`}
          onClick={() => send(act, 'reset_key', { language: languageKey })}
        />
      )}
      </Box>
      {problem && (
        <Box color="bad" fontSize="0.85em">
          {problem}
        </Box>
      )}
    </Box>
  );
};
