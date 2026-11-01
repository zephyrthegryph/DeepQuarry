// DQAdd — Language picker.
//
// Three panels:
//   1. Prefix keys — the three single-character shortcuts the player binds for
//      :1 :2 :3 style language prefixes. Each button shows the currently bound
//      character (or "unset" if blank); clicking opens a server-side prompt to
//      type the new character.
//   2. Languages — full catalogue with Add/Remove and an optional per-language
//      custom key binding. Restricted entries surface why they're restricted
//      and disable their Add button.
//   3. Footer — species default + total picked counter so the user always knows
//      how many slots are left.

import { useState } from 'react';
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
  language_prefixes: string[];
  language_custom_keys: Record<string, string>;
  preferred_language: string | null;
  runechat_color: string;
  extra_languages: number;
  max_alternate_languages: number;
  species_default_language: string | null;
  /// The languages this character may pick (server rule); undefined while an old payload is cached.
  pickable_languages?: string[];
};

type LangStatic = {
  all_languages: Record<
    string,
    { name: string; desc: string; restricted: boolean }
  >;
};

type Act = ReturnType<typeof useBackend>['act'];

const send = (act: Act, action: string, params: Record<string, unknown>) =>
  act('dq_editor_action', { editor: 'language', action, params });

type LangMeta = { name: string; desc: string; restricted: boolean };

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
  const max = d.max_alternate_languages ?? 0;
  const room = Math.max(0, max - selected.size);

  // Reverse the {key → language} map so we can show a language's key with the
  // language. One key may only bind one language.
  const langToKey: Record<string, string> = {};
  for (const [k, lang] of Object.entries(d.language_custom_keys ?? {})) {
    langToKey[lang] = k;
  }

  // The server names the languages this character may actually pick; anything else (restricted, whitelisted for someone
  // else) is not listed at all. Selected ones come first, then the rest alphabetically; the search narrows both.
  const pickable = d.pickable_languages ? new Set(d.pickable_languages) : null;
  const [search, setSearch] = useState('');
  const sortedLanguageEntries = filterLanguages(
    Object.entries(all),
    pickable,
    selected,
    search,
  );
  return (
    <Stack vertical>
      <Stack.Item>
        <PrefixPanel prefixes={d.language_prefixes ?? []} act={act} />
      </Stack.Item>

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
            default. Bind a single-character "key" to a language to switch to it
            in chat with that key.
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
                roomLeft={room}
                customKey={langToKey[key]}
                act={act}
              />
            ))}
          </Box>
        </Section>
      </Stack.Item>
    </Stack>
  );
};

// ─── Prefix keys panel ────────────────────────────────────────────────────────────

const PrefixPanel = ({ prefixes, act }: { prefixes: string[]; act: Act }) => (
  <Section
    title={
      <Stack align="center">
        <Stack.Item>
          <Icon name="key" mr={0.5} />
          Prefix Keys
        </Stack.Item>
      </Stack>
    }
  >
    <Box mb={1} fontSize="0.85em" color="label">
      Type one of these characters in chat as a prefix to broadcast on the
      matching language slot — for example, with{' '}
      <Box inline bold color="white">
        {prefixes[0] || ':'}
      </Box>{' '}
      bound, typing{' '}
      <Box inline bold color="white" style={{ fontFamily: 'monospace' }}>
        {`${prefixes[0] || ':'}hello`}
      </Box>{' '}
      sends "hello" on slot 1's language. Click a slot to rebind.
    </Box>
    <Stack>
      {[1, 2, 3].map((idx) => (
        <Stack.Item key={idx}>
          <PrefixSlot
            index={idx}
            char={prefixes[idx - 1] ?? ''}
            onClick={() => send(act, 'set_prefix', { index: idx })}
          />
        </Stack.Item>
      ))}
      <Stack.Item grow />
      <Stack.Item>
        <Button
          icon="rotate-left"
          onClick={() => send(act, 'reset_prefixes', {})}
        >
          Reset to defaults
        </Button>
      </Stack.Item>
    </Stack>
  </Section>
);

const PrefixSlot = ({
  index,
  char,
  onClick,
}: {
  index: number;
  char: string;
  onClick: () => void;
}) => (
  <Tooltip
    content={
      char
        ? `Slot ${index}: bound to "${char}"`
        : `Slot ${index}: unbound (click to set)`
    }
  >
    <Box
      onClick={onClick}
      style={{
        cursor: 'pointer',
        width: '7.333em',
        padding: '0.333em 0.5em',
        borderRadius: '0.5em',
        border: `1px solid ${
          char ? 'rgba(52,152,219,0.6)' : 'rgba(255,255,255,0.18)'
        }`,
        background: char ? 'rgba(52,152,219,0.12)' : 'rgba(255,255,255,0.04)',
        transition: 'all 120ms',
      }}
    >
      <Box
        style={{
          fontSize: '0.62em',
          color: 'rgba(255,255,255,0.5)',
          letterSpacing: '0.1em',
          textTransform: 'uppercase',
        }}
      >
        Slot {index}
      </Box>
      <Box
        style={{
          fontSize: '1.5em',
          fontWeight: 'bold',
          fontFamily: 'monospace',
          lineHeight: '1',
          color: char ? '#fff' : 'rgba(255,255,255,0.35)',
        }}
      >
        {char || '—'}
      </Box>
    </Box>
  </Tooltip>
);

// ─── Single language row ──────────────────────────────────────────────────────────

const LanguageRow = ({
  languageKey,
  meta,
  selected,
  roomLeft,
  customKey,
  act,
}: {
  languageKey: string;
  meta: { name: string; desc: string; restricted: boolean };
  selected: boolean;
  roomLeft: number;
  customKey?: string;
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
        background: selected
          ? 'rgba(52,152,219,0.08)'
          : 'rgba(255,255,255,0.03)',
        border: selected
          ? '1px solid rgba(52,152,219,0.45)'
          : '1px solid rgba(255,255,255,0.06)',
        opacity: isRestricted ? 0.55 : 1,
      }}
    >
      <Stack align="center">
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
        {selected && (
          <Stack.Item>
            <Button
              icon={customKey ? 'keyboard' : 'plus'}
              tooltip={
                customKey
                  ? `Bound to key "${customKey}" — click to rebind`
                  : 'Bind a single-character key to this language'
              }
              onClick={() =>
                send(act, 'set_custom_key', { language: languageKey })
              }
            >
              {customKey ? `key: ${customKey}` : 'set key'}
            </Button>
            {customKey && (
              <Button
                ml={0.5}
                icon="xmark"
                color="bad"
                tooltip="Unbind this language's key"
                onClick={() =>
                  send(act, 'clear_custom_key', { language: languageKey })
                }
              />
            )}
          </Stack.Item>
        )}
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
      </Stack>
    </Box>
  );
};
