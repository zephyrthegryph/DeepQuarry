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
  preview,
  buttonsBelow,
  actions,
}: {
  entries: SwitcherEntry[];
  onCommit: (key: string, value: string) => void;
  preview?: ReactNode;
  /// The entry buttons as a row under the text box instead of a column beside it.
  buttonsBelow?: boolean;
  /// Extra controls shown with the preview (e.g. inspect in game).
  actions?: ReactNode;
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
      {preview && <TextPreview actions={actions}>{preview}</TextPreview>}
    </Box>
  );
};

/// Framed "Preview" block.
export const TextPreview = ({
  children,
  actions,
}: {
  children: ReactNode;
  actions?: ReactNode;
}) => (
  <Box
    mt={0.5}
    p={0.5}
    style={{
      border: '1px solid rgba(255,255,255,0.12)',
      borderRadius: '0.25em',
      background: 'rgba(0,0,0,0.2)',
    }}
  >
    <Box
      mb={0.25}
      style={{ display: 'flex', alignItems: 'center', gap: '0.5em' }}
    >
      <Box color="label" fontSize="0.85em" style={{ flex: '1 1 auto' }}>
        Preview
      </Box>
      {actions}
    </Box>
    {children}
  </Box>
);

/// The flavor text as examine prints it: the entries in order, a blank line apart, "||" stripped.
export const flavorPreviewText = (
  zones: string[],
  texts: Record<string, string>,
) =>
  zones
    .map((z) => (texts[z] ?? '').replaceAll('||', ''))
    .filter((t) => t)
    .join('\n\n');

/// The OOC notes as the notes window shows them; private notes are nobody else's, so they stay out.
export const OOC_PREVIEW_SECTIONS: [string, string][] = [
  ['OOC_Notes_Favs', 'Favourites'],
  ['OOC_Notes_Likes', 'Likes'],
  ['OOC_Notes_Maybes', 'Maybes'],
  ['OOC_Notes_Disikes', 'Dislikes'],
];

export const OocPreview = ({ values }: { values: Record<string, unknown> }) => {
  const notes = String(values.OOC_Notes ?? '');
  const sections = OOC_PREVIEW_SECTIONS.filter(([key]) => values[key]);
  if (!notes && !sections.length) {
    return (
      <Box color="label" italic>
        Nothing to show yet.
      </Box>
    );
  }
  return (
    <Box>
      {notes && <Box preserveWhitespace>{notes}</Box>}
      {sections.map(([key, title]) => (
        <Box key={key} mt={0.5}>
          <Box bold>{title}</Box>
          <Box preserveWhitespace>{String(values[key])}</Box>
        </Box>
      ))}
    </Box>
  );
};
