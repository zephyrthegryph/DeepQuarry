// DQAdd — search across every character setup setting. The index is built on the client from
// the category structures it already caches (every tab arrives with the prefetch), so it costs
// the server nothing: pref labels, group names, category names and editor names, each pointing
// at an anchor (`data-dq-anchor`) the page renders. Picking a result switches tabs as needed,
// scrolls the anchor into view and highlights it for a moment.

import { createContext, useContext, useMemo, useState } from 'react';
import { Box, Button, Input } from 'tgui-core/components';
import { labelForCategory, labelForGroup, labelForKey } from './labels';
import type { PrefCategory } from './types';

/// Extra words an editor answers to (its display name and key are always searched).
const EDITOR_KEYWORDS: Record<string, string> = {
  antag_optin: 'antagonist opt in roles',
  birthday: 'birthday age date',
  body_markings: 'markings tattoos scars stripes spots',
  faction_affiliations: 'factions affiliation reputation',
  flavor: 'flavor flavour text description examine',
  language: 'languages speech prefix',
  loadout: 'loadout gear items clothes underwear equipment',
  mind_body: 'mind body perks',
  nif_status: 'nif neural interface',
  occupation: 'jobs occupation roles priority department',
  organs: 'organs limbs prosthetic amputated robotic cybernetic',
  persistence: 'persistence resleeve backup scan',
  robot_chassis: 'chassis module sprite robot cyborg',
  species_picker: 'species race robot pai custom',
  trait_picker: 'traits quirks perks',
  vore_messages: 'vore messages thermal',
};

export type SearchHit = {
  /// The category the anchor lives in.
  category: string;
  /// data-dq-anchor value on the page ('' = just the tab).
  anchor: string;
  label: string;
  /// Where it is, for the result list ("Looks › Hair").
  where: string;
  kind: 'setting' | 'group' | 'tab' | 'editor';
  text: string;
};

export const prefAnchor = (key: string) => `pref:${key}`;
export const groupAnchor = (category: string, group: string) =>
  `group:${category}/${group}`;
export const editorAnchor = (key: string) => `editor:${key}`;

export const buildSearchIndex = (
  categoryIndex: string[],
  categories: Record<string, PrefCategory>,
): SearchHit[] => {
  const hits: SearchHit[] = [];
  for (const category of categoryIndex) {
    const catLabel = labelForCategory(category);
    hits.push({
      category,
      anchor: '',
      label: catLabel,
      where: 'Tab',
      kind: 'tab',
      text: `${catLabel} ${category}`.toLowerCase(),
    });
    const page = categories[category];
    if (!page) continue;
    for (const group of page.groups) {
      const groupLabel = group.group ? labelForGroup(group.group) : '';
      if (group.group) {
        hits.push({
          category,
          anchor: groupAnchor(category, group.group),
          label: groupLabel,
          where: catLabel,
          kind: 'group',
          text: `${groupLabel} ${group.group}`.toLowerCase(),
        });
      }
      const where = groupLabel ? `${catLabel} › ${groupLabel}` : catLabel;
      for (const item of group.items) {
        if (item.type === 'widget') {
          if (item.widget === 'hidden') continue;
          const label = labelForKey(item.key, item.label);
          hits.push({
            category,
            anchor: prefAnchor(item.key),
            label,
            where,
            kind: 'setting',
            text: `${label} ${item.key.replace(/_/g, ' ')}`.toLowerCase(),
          });
        } else {
          const label = item.display_name || labelForKey(item.key);
          hits.push({
            category,
            anchor: editorAnchor(item.key),
            label,
            where,
            kind: 'editor',
            text: `${label} ${item.key.replace(/_/g, ' ')} ${
              EDITOR_KEYWORDS[item.key] ?? ''
            }`.toLowerCase(),
          });
        }
      }
    }
  }
  return hits;
};

/// Every word of the query must appear; a label that starts with the query ranks first.
export const searchSettings = (hits: SearchHit[], query: string) => {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  const words = q.split(/\s+/);
  const kindRank = { setting: 0, editor: 1, group: 2, tab: 3 };
  return hits
    .filter((hit) => words.every((w) => hit.text.includes(w)))
    .map((hit) => {
      const label = hit.label.toLowerCase();
      const score =
        (label === q
          ? 0
          : label.startsWith(q)
            ? 1
            : label.includes(q)
              ? 2
              : 3) *
          10 +
        kindRank[hit.kind];
      return { hit, score };
    })
    .sort((a, b) => a.score - b.score || a.hit.label.localeCompare(b.hit.label))
    .slice(0, 14)
    .map((r) => r.hit);
};

/// The anchor being highlighted after a search jump (rows compare against it).
export const SearchHighlightContext = createContext<string | null>(null);

export const useSearchHighlight = (anchor: string) =>
  useContext(SearchHighlightContext) === anchor;

/// Inline style for a highlighted anchor: an outline that does not move the layout.
export const highlightStyle = (on: boolean) =>
  on
    ? {
        outline: '0.15em solid var(--color-yellow, #e6c84c)',
        outlineOffset: '0.1em',
        borderRadius: '0.2em',
        background: 'rgba(230, 200, 76, 0.12)',
        transition: 'background 0.3s',
      }
    : undefined;

export const SettingsSearch = ({
  hits,
  onPick,
}: {
  hits: SearchHit[];
  onPick: (hit: SearchHit) => void;
}) => {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const results = useMemo(() => searchSettings(hits, query), [hits, query]);
  const pick = (hit: SearchHit) => {
    onPick(hit);
    setOpen(false);
  };
  return (
    <Box
      style={{ position: 'relative', flex: '1 1 14em', maxWidth: '24em' }}
      onKeyDown={(e) => {
        if (e.key === 'Escape') setOpen(false);
      }}
    >
      <Input
        fluid
        placeholder="Search settings…"
        value={query}
        onChange={(v) => {
          setQuery(v);
          setOpen(true);
        }}
        onEnter={() => {
          if (results[0]) pick(results[0]);
        }}
        onBlur={() => setTimeout(() => setOpen(false), 200)}
      />
      {open && query.trim() !== '' && (
        <Box
          className="dq-search-results"
          style={{
            position: 'absolute',
            top: '100%',
            left: 0,
            right: 0,
            minWidth: '18em',
            zIndex: 50,
            maxHeight: '22em',
            overflowY: 'auto',
            background: 'var(--color-base, #252525)',
            border: '0.0833em solid rgba(255,255,255,0.2)',
            borderRadius: '0.2em',
            boxShadow: '0 0.3em 1em rgba(0,0,0,0.6)',
            padding: '0.2em',
          }}
        >
          {results.length === 0 && (
            <Box color="label" italic p={0.5}>
              No setting matches “{query.trim()}”.
            </Box>
          )}
          {results.map((hit) => (
            <Button
              key={`${hit.category}|${hit.anchor}|${hit.label}`}
              fluid
              color="transparent"
              onMouseDown={(e) => e.preventDefault()}
              onClick={() => pick(hit)}
            >
              <Box
                style={{
                  display: 'flex',
                  gap: '0.5em',
                  alignItems: 'baseline',
                  minWidth: 0,
                }}
              >
                <Box
                  style={{
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {hit.label}
                </Box>
                <Box
                  color="label"
                  style={{
                    marginLeft: 'auto',
                    fontSize: '0.85em',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {hit.where}
                </Box>
              </Box>
            </Button>
          ))}
        </Box>
      )}
    </Box>
  );
};
