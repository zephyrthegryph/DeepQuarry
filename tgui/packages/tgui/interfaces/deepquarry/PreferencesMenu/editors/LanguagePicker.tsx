// DQAdd — Language picker. One list of the languages the character knows or may learn. Each known one has
// a preferred-language radio (the language spoken by default) and its own key, typed after the chat prefix
// to speak it. A key another known language holds is refused here and again on the server.

import { useEffect, useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Icon,
  Input,
  Section,
  Stack,
  Tooltip,
} from 'tgui-core/components';
import type { EditorProps } from './index';

type LangData = {
  alternate_languages: string[];
  /// Language name -> the key that speaks it for this character.
  language_keys: Record<string, string>;
  known_languages: string[];
  language_prefix: string;
  preferred_language: string | null;
  extra_languages: number;
  max_alternate_languages: number;
  species_default_language: string | null;
  /// The languages this character may pick (server rule); undefined while an old payload is cached.
  pickable_languages?: string[];
};

type LangStatic = {
  all_languages: Record<
    string,
    LangMeta
  >;
};

type Act = ReturnType<typeof useBackend>['act'];

const send = (act: Act, action: string, params: Record<string, unknown>) =>
  act('dq_editor_action', { editor: 'language', action, params });

type LangMeta = {
  name: string;
  desc: string;
  restricted: boolean;
  default_key?: string;
};

/// Why `key` cannot speak `language`, or null when it can: the rule ui_act_set_key applies on the server.
export const languageKeyProblem = (
  key: string,
  language: string,
  keys: Record<string, string>,
): string | null => {
  if (!/^[A-Za-z0-9]$/.test(key)) return 'One letter or digit.';
  for (const [other, held] of Object.entries(keys)) {
    if (other !== language && held === key) return `Already speaks ${other}.`;
  }
  return null;
};

/// The rows to list: unrestricted, pickable by this character (or already picked), matching the search; picked first.
export const filterLanguages = (
  entries: [string, LangMeta][],
  pickable: Set<string> | null,
  selected: Set<string>,
  search: string,
): [string, LangMeta][] => {
  const q = search.trim().toLowerCase();
  return entries
    .filter(
      ([key, meta]) =>
        selected.has(key) ||
        (!meta.restricted && (!pickable || pickable.has(key))),
    )
    .filter(
      ([, meta]) =>
        !q ||
        meta.name.toLowerCase().includes(q) ||
        meta.desc.toLowerCase().includes(q),
    )
    .sort((x, y) => {
      const xs = selected.has(x[0]) ? 0 : 1;
      const ys = selected.has(y[0]) ? 0 : 1;
      return xs - ys || x[1].name.localeCompare(y[1].name);
    });
};

export const LanguagePicker = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = (data ?? {}) as LangData;
  const s = (staticData ?? {}) as LangStatic;

  const all = s.all_languages ?? {};
  const selected = new Set(d.alternate_languages ?? []);
  const known = new Set(d.known_languages ?? []);
  const max = d.max_alternate_languages ?? 0;
  const room = Math.max(0, max - selected.size);
  const keys = d.language_keys ?? {};
  const prefix = d.language_prefix ?? ',';

  // The server names the languages this character may actually pick; anything else (restricted, whitelisted for someone
  // else) is not listed at all. Selected ones come first, then the rest alphabetically; the search narrows both.
  const pickable = d.pickable_languages ? new Set(d.pickable_languages) : null;
  const [search, setSearch] = useState('');
  const sortedLanguageEntries = filterLanguages(
    Object.entries(all),
    pickable,
    new Set([...selected, ...known]),
    search,
  );
  return (
    <Stack vertical>
      <Stack.Item>
        <Section
          title={
            <Stack align="center">
              <Stack.Item>
                <Icon name="language" mr={0.5} />
                Languages
              </Stack.Item>
              <Stack.Item grow />
              <Stack.Item>
                <Box
                  style={{
                    padding: '0.167em 0.667em',
                    borderRadius: '0.833em',
                    backgroundColor:
                      room === 0
                        ? 'rgba(231,76,60,0.2)'
                        : 'rgba(255,255,255,0.06)',
                    color: room === 0 ? '#E74C3C' : '#fff',
                    fontWeight: 'bold',
                    fontSize: '0.85em',
                  }}
                >
                  {selected.size} / {max} picked
                </Box>
              </Stack.Item>
            </Stack>
          }
        >
          <Box mb={1} fontSize="0.85em" color="label">
            Pick up to{' '}
            <Box inline bold color="white">
              {max}
            </Box>{' '}
            alternate languages your character knows on top of their species
            default. The circle marks the language spoken by default. To speak
            another in chat, type{' '}
            <Box inline bold color="white" style={{ fontFamily: 'monospace' }}>
              {prefix}
            </Box>{' '}
            then its key.
          </Box>
          {d.species_default_language && (
            <Box
              mb={1}
              p={0.5}
              style={{
                borderLeft: '0.25em solid rgba(255,255,255,0.3)',
                paddingLeft: '0.667em',
                background: 'rgba(255,255,255,0.04)',
                fontSize: '0.9em',
              }}
            >
              <Icon
                name="circle-info"
                mr={0.5}
                style={{ color: 'rgba(255,255,255,0.5)' }}
              />
              Species default:{' '}
              <Box inline bold>
                {d.species_default_language}
              </Box>
            </Box>
          )}
          <Input
            fluid
            mb={0.5}
            placeholder={`Search ${pickable ? pickable.size + selected.size : Object.keys(all).length} languages...`}
            value={search}
            onChange={setSearch}
          />
          <Box style={{ maxHeight: '20em', overflowY: 'auto' }}>
            {sortedLanguageEntries.length === 0 && (
              <Box color="label" italic>
                No language matches.
              </Box>
            )}
            {sortedLanguageEntries.map(([key, meta]) => (
              <LanguageRow
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
        </Section>
      </Stack.Item>
    </Stack>
  );
};

// ─── Single language row ──────────────────────────────────────────────────────────

const LanguageRow = ({
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
  // tgui sends BooleanLike (0/1) for booleans. `meta.restricted && (…)` with a
  // 0 would render literal "0" next to the language name. Coerce to a real
  // boolean before the conditional. (Restricted entries are filtered upstream
  // in sortedLanguageEntries, but keep the guard so a future caller can render
  // a single LanguageRow without surprises.)
  const isRestricted = !!meta.restricted;
  const hasDesc = !!meta.desc;
  const disabled = isRestricted || (!selected && roomLeft === 0);
  return (
    <Box
      mb={0.25}
      px={0.75}
      py={0.25}
      style={{
        borderRadius: '0.333em',
        background: known
          ? 'rgba(52,152,219,0.08)'
          : 'rgba(255,255,255,0.03)',
        border: known
          ? '1px solid rgba(52,152,219,0.45)'
          : '1px solid rgba(255,255,255,0.06)',
        opacity: isRestricted ? 0.55 : 1,
      }}
    >
      <Stack align="center">
        {known && (
          <Stack.Item>
            <Button
              compact
              icon={preferred ? 'circle-dot' : 'circle'}
              selected={preferred}
              tooltip={
                preferred
                  ? 'Spoken by default'
                  : 'Speak this language by default'
              }
              onClick={() =>
                send(act, 'set_preferred', { language: languageKey })
              }
            />
          </Stack.Item>
        )}
        <Stack.Item grow>
          <Tooltip content={hasDesc ? meta.desc : meta.name}>
            <Box
              bold
              style={{
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
              }}
            >
              {meta.name}
              {isRestricted && (
                <Box
                  inline
                  ml={1}
                  style={{
                    fontSize: '0.72em',
                    padding: '0 0.5em',
                    borderRadius: '0.667em',
                    backgroundColor: 'rgba(231,76,60,0.2)',
                    color: '#E74C3C',
                    fontWeight: 'bold',
                  }}
                >
                  RESTRICTED
                </Box>
              )}
            </Box>
          </Tooltip>
        </Stack.Item>
        {known && (
          <Stack.Item>
            <LanguageKeyInput
              languageKey={languageKey}
              defaultKey={meta.default_key ?? ''}
              keys={keys}
              act={act}
            />
          </Stack.Item>
        )}
        {(selected || !known) && (
          <Stack.Item>
            <Button
              ml={0.5}
              icon={selected ? 'minus' : 'plus'}
              color={selected ? 'bad' : 'good'}
              disabled={disabled}
              onClick={() =>
                selected
                  ? send(act, 'remove_language', { language: languageKey })
                  : send(act, 'add_language', { language: languageKey })
              }
            >
              {selected ? 'Remove' : 'Add'}
            </Button>
          </Stack.Item>
        )}
      </Stack>
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
    <Box inline>
      {problem && (
        <Box inline color="bad" mr={0.5} fontSize="0.85em">
          {problem}
        </Box>
      )}
      <Box inline color="label" mr={0.25}>
        Key
      </Box>
      <Input
        width="2.5em"
        maxLength={1}
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
          tooltip={`Back to its own key (${defaultKey})`}
          onClick={() => send(act, 'reset_key', { language: languageKey })}
        />
      )}
    </Box>
  );
};
