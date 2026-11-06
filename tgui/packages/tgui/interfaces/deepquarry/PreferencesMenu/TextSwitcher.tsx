// DQAdd — A button list choosing which text is edited and one editor; the editor can show the chat's formatting
// in place. Flavor, speech verbs, records and OOC notes all use it.

import { type ReactNode, useEffect, useState } from 'react';
import { Box, Button, Input, TextArea } from 'tgui-core/components';
import { FormattingTextArea } from './FormattingTextArea';

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
  formatted,
}: {
  entries: SwitcherEntry[];
  onCommit: (key: string, value: string) => void;
  /// The entry buttons as a row under the text box instead of a column beside it.
  buttonsBelow?: boolean;
  /// Controls in the row of entry buttons (e.g. inspect in game).
  actions?: ReactNode;
  /// The box shows the chat's emphasis as it is typed, and takes the chat's Ctrl+B/I/U.
  formatted?: boolean;
}) => {
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
  const editor = entry.short ? (
    <Input
      fluid
      maxLength={entry.maxLength}
      value={draft}
      onChange={setDraft}
      onBlur={commit}
      onEnter={commit}
    />
  ) : formatted ? (
    <FormattingTextArea
      maxLength={entry.maxLength}
      value={draft}
      onChange={setDraft}
      onBlur={commit}
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
            {actions && <Box style={{ marginLeft: 'auto' }}>{actions}</Box>}
          </Box>
        </Box>
      ) : (
        <Box style={{ display: 'flex', gap: '0.5em', alignItems: 'stretch' }}>
          <Box style={{ flex: '0 0 auto', minWidth: '7em' }}>{buttons}</Box>
          <Box style={{ flex: '1 1 0', minWidth: 0 }}>{editor}</Box>
        </Box>
      )}
    </Box>
  );
};

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
