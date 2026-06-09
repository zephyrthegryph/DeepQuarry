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

import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Icon,
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
};

type LangStatic = {
  all_languages: Record<
    string,
    { name: string; desc: string; restricted: boolean }
  >;
};

type Act = ReturnType<typeof useBackend>['act'];

const send = (
  act: Act,
  action: string,
  params: Record<string, unknown>,
) => act('dq_editor_action', { editor: 'language', action, params });

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

  // Display order: selected languages first (so the player's working set sits
  // at the top), then unselected alphabetically. Restricted entries are
  // filtered out entirely — the user can't pick them anyway.
  const sortedLanguageEntries = Object.entries(all)
    .filter(([, meta]) => !meta.restricted)
    .sort((a, b) => {
      const aSel = selected.has(a[0]) ? 0 : 1;
      const bSel = selected.has(b[0]) ? 0 : 1;
      if (aSel !== bSel) return aSel - bSel;
      return a[1].name.localeCompare(b[1].name);
    });

  return (
    <Stack vertical>
      <Stack.Item>
        <PrefixPanel
          prefixes={d.language_prefixes ?? []}
          act={act}
        />
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
                    padding: '2px 8px',
                    borderRadius: '10px',
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
                borderLeft: '3px solid rgba(255,255,255,0.3)',
                paddingLeft: '8px',
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
        </Section>
      </Stack.Item>
    </Stack>
  );
};

// ─── Prefix keys panel ────────────────────────────────────────────────────────────

const PrefixPanel = ({
  prefixes,
  act,
}: {
  prefixes: string[];
  act: Act;
}) => (
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
      <Box
        inline
        bold
        color="white"
        style={{ fontFamily: 'monospace' }}
      >
        {(prefixes[0] || ':') + 'hello'}
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
        width: '88px',
        padding: '4px 6px',
        borderRadius: '6px',
        border: `1px solid ${
          char ? 'rgba(52,152,219,0.6)' : 'rgba(255,255,255,0.18)'
        }`,
        background: char
          ? 'rgba(52,152,219,0.12)'
          : 'rgba(255,255,255,0.04)',
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
      mb={0.5}
      px={1}
      py={0.5}
      style={{
        borderRadius: '4px',
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
          <Box bold>
            {meta.name}
            {isRestricted && (
              <Tooltip content="This language is restricted — only certain characters or roles can speak it.">
                <Box
                  inline
                  ml={1}
                  style={{
                    fontSize: '0.72em',
                    padding: '0 6px',
                    borderRadius: '8px',
                    backgroundColor: 'rgba(231,76,60,0.2)',
                    color: '#E74C3C',
                    fontWeight: 'bold',
                  }}
                >
                  RESTRICTED
                </Box>
              </Tooltip>
            )}
          </Box>
          {hasDesc && (
            <Box fontSize="0.82em" color="label" mt={0.25}>
              {meta.desc}
            </Box>
          )}
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
