// DQAdd — A button list choosing which text is edited, one editor beside it, and optionally a preview of how
// the texts read. Flavor, speech verbs, records and OOC notes all use it.

import { type ReactNode, useEffect, useState } from 'react';
import { Box, Button, Input, TextArea } from 'tgui-core/components';

export type SwitcherEntry = {
  key: string;
  label: string;
  value: string;
  /// Shown when the value is empty, and stored as empty when typed back.
  defaultText?: string;
  maxLength?: number;
  /// A one-line box rather than a tall text area.
  short?: boolean;
};

/// What an editor box shows for a stored value.
export const shownText = (value: string, defaultText?: string) =>
  value || defaultText || '';

/// What to store for what the box holds: a default stays unset, so what it stands for can still vary.
export const storedText = (typed: string, defaultText?: string) =>
  defaultText !== undefined &&
  (typed.trim() === '' || typed.trim() === defaultText)
    ? ''
    : typed;

export const TextSwitcher = ({
  entries,
  onCommit,
  buttonsBelow,
  actions,
  render,
}: {
  entries: SwitcherEntry[];
  onCommit: (key: string, value: string) => void;
  /// The entry buttons as a row under the text box instead of a column beside it.
  buttonsBelow?: boolean;
  /// Controls under the editor (e.g. inspect in game).
  actions?: ReactNode;
  /// How the text reads in game; given, a Formatted toggle shows it in place of the box.
  render?: (text: string) => ReactNode;
}) => {
  const [formatted, setFormatted] = useState(false);
  const [picked, setPicked] = useState(entries[0]?.key ?? '');
  const entry = entries.find((e) => e.key === picked) ?? entries[0];
  const shown = entry ? shownText(entry.value, entry.defaultText) : '';
  const [draft, setDraft] = useState(shown);
  // Switching entries, or the server pushing a new value, replaces the buffer.
  useEffect(() => {
    setDraft(shown);
  }, [entry?.key, shown]);
  if (!entry) return null;

  const commit = () => {
    const value = storedText(draft, entry.defaultText);
    if (value !== entry.value) onCommit(entry.key, value);
  };
  const buttons = entries.map((e) => (
    <Button
      key={e.key}
      fluid={!buttonsBelow}
      selected={e.key === entry.key}
      onClick={() => setPicked(e.key)}
    >
      {e.label}
    </Button>
  ));
  const editor = render && formatted ? (
    <Box
      p={0.5}
      style={{
        minHeight: '10em',
        border: '1px solid rgba(255,255,255,0.12)',
        borderRadius: '0.25em',
        background: 'rgba(0,0,0,0.2)',
        overflowWrap: 'anywhere',
      }}
    >
      {draft ? (
        render(draft)
      ) : (
        <Box color="label" italic>
          Nothing written.
        </Box>
      )}
    </Box>
  ) : entry.short ? (
    <Input
      fluid
      maxLength={entry.maxLength}
      value={draft}
      onChange={setDraft}
      onBlur={commit}
      onEnter={commit}
    />
  ) : (
    <TextArea
      fluid
      height="10em"
      maxLength={entry.maxLength}
      value={draft}
      onChange={setDraft}
      onBlur={commit}
    />
  );
  return (
    <Box>
      {buttonsBelow ? (
        <Box>
          {editor}
          <Box
            mt={0.25}
            style={{ display: 'flex', flexWrap: 'wrap', gap: '0.25em' }}
          >
            {buttons}
          </Box>
        </Box>
      ) : (
        <Box style={{ display: 'flex', gap: '0.5em', alignItems: 'stretch' }}>
          <Box style={{ flex: '0 0 auto', minWidth: '7em' }}>{buttons}</Box>
          <Box style={{ flex: '1 1 0', minWidth: 0 }}>{editor}</Box>
        </Box>
      )}
      {(render || actions) && (
        <Box mt={0.25} style={{ display: 'flex', gap: '0.25em' }}>
          {render && (
            <Button
              compact
              icon={formatted ? 'pen' : 'eye'}
              selected={formatted}
              tooltip="Show the text the way it reads in game"
              onClick={() => setFormatted(!formatted)}
            >
              {formatted ? 'Edit' : 'Formatted'}
            </Button>
          )}
          {actions}
        </Box>
      )}
    </Box>
  );
};

/// Flavor as examine renders it: "||" marks spoilers (hidden until hovered), line breaks kept.
export const renderFlavor = (text: string): ReactNode => (
  <Box preserveWhitespace>
    {splitSpoilers(text).map(([part, spoiler], i) =>
      spoiler ? (
        <span
          key={i}
          title="Spoiler"
          style={{ background: '#000', color: '#000', borderRadius: '0.2em' }}
        >
          {part}
        </span>
      ) : (
        <span key={i}>{part}</span>
      ),
    )}
  </Box>
);

/// Plain text as the notes and records windows show it: line breaks kept.
export const renderPlain = (text: string): ReactNode => (
  <Box preserveWhitespace>{text}</Box>
);

/// The parts of a flavor text and whether each is a spoiler (between "||" pairs), as topic_flavor_more splits it.
export const splitSpoilers = (text: string): [string, boolean][] =>
  text
    .split('||')
    .map((part, i): [string, boolean] => [part, i % 2 === 1])
    .filter(([part]) => part !== '');

/// The flavor text as examine prints it: the entries in order, a blank line apart, "||" stripped.
export const flavorPreviewText = (
  zones: string[],
  texts: Record<string, string>,
) =>
  zones
    .map((z) => (texts[z] ?? '').replaceAll('||', ''))
    .filter((t) => t)
    .join('\n\n');
