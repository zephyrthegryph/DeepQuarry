// DQAdd — Species picker editor.
//
// Trigger row: a card showing the currently-selected species' thumbnail +
// name + short pitch, plus an inline "Display name" text input below so the
// player can override the species name shown to others without picking a
// dedicated "Custom Species" placeholder species.
//
// Clicking Change opens a fullscreen modal — a grid of cards each showing
// a sprite thumbnail + name + 1-line pitch + a Details toggle that expands
// the full blurb (HTML-rendered) below the card with internal scroll.
//
// Synthetic Robot/pAI cards are pinned to the top with a purple tint and a
// "(synthetic)" tag so they stand out from real species.

import { useEffect, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Box, Button, Input, Stack } from 'tgui-core/components';
import { HtmlRenderer } from '../../../common/HtmlRenderer';
import type { EditorProps } from './index';

type Data = {
  current_species: string;
  custom_species: string;
};

type SpeciesMeta = {
  name: string;
  pitch: string;
  blurb: string;
  thumb_b64?: string;
};

type Static = {
  all_species: Record<string, SpeciesMeta>;
};

const send = (
  act: ReturnType<typeof useBackend>['act'],
  action: string,
  params: Record<string, unknown>,
) => act('dq_editor_action', { editor: 'species_picker', action, params });

export const SpeciesPicker = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as Data;
  const s = (staticData ?? {}) as Static;
  const [open, setOpen] = useState(false);
  const [customSpecies, setCustomSpecies] = useState(d.custom_species);

  // Resync the local draft of the display-name override when the server
  // value changes (initial load, slot switch). Without this guard the
  // first server push overwrites a draft the user is actively typing.
  useEffect(() => {
    setCustomSpecies(d.custom_species);
  }, [d.custom_species]);

  const allSpecies = s.all_species ?? {};
  const currentMeta = allSpecies[d.current_species];

  return (
    <>
      <Stack align="center">
        {currentMeta?.thumb_b64 && (
          <Stack.Item>
            <img
              src={`data:image/png;base64,${currentMeta.thumb_b64}`}
              alt=""
              width={48}
              height={48}
              style={{ imageRendering: 'pixelated' }}
            />
          </Stack.Item>
        )}
        <Stack.Item grow style={{ minWidth: 0 }}>
          <Box bold>{currentMeta?.name ?? d.current_species}</Box>
          {currentMeta?.pitch && (
            <Box color="label" fontSize="0.85em">
              {currentMeta.pitch}
            </Box>
          )}
        </Stack.Item>
        <Stack.Item>
          <Button icon="pen" onClick={() => setOpen(true)}>
            Change
          </Button>
        </Stack.Item>
      </Stack>
      <Box mt={0.5}>
        <Box fontSize="0.78em" color="label" mb={0.25}>
          Display name (optional — shown to others in place of the species name)
        </Box>
        <Input
          fluid
          placeholder={currentMeta?.name ?? ''}
          value={customSpecies}
          onChange={(v) => setCustomSpecies(v)}
          onBlur={() => {
            if (customSpecies !== d.custom_species) {
              send(act, 'set_custom_species', { value: customSpecies });
            }
          }}
        />
      </Box>
      {open && (
        <SpeciesPickerModal
          allSpecies={allSpecies}
          currentKey={d.current_species}
          onPick={(key) => {
            send(act, 'set_species', { value: key });
            setOpen(false);
          }}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  );
};

const stripHtml = (s: string): string => s.replace(/<[^>]*>/g, '');

type ModalProps = {
  allSpecies: Record<string, SpeciesMeta>;
  currentKey: string;
  onPick: (key: string) => void;
  onClose: () => void;
};

const SpeciesPickerModal = ({
  allSpecies,
  currentKey,
  onPick,
  onClose,
}: ModalProps) => {
  const [search, setSearch] = useState('');
  const lcSearch = search.trim().toLowerCase();
  const filteredEntries = Object.entries(allSpecies)
    .filter(
      ([, meta]) =>
        !lcSearch ||
        meta.name.toLowerCase().includes(lcSearch) ||
        (meta.pitch?.toLowerCase() ?? '').includes(lcSearch) ||
        stripHtml(meta.blurb ?? '').toLowerCase().includes(lcSearch),
    )
    .sort(([keyA, a], [keyB, b]) => {
      // Pin synthetic entries to the top so they're seen first.
      const synA = keyA.startsWith('_');
      const synB = keyB.startsWith('_');
      if (synA !== synB) return synA ? -1 : 1;
      return a.name.localeCompare(b.name);
    });

  return (
    <Box
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 1000,
        background: 'rgba(0,0,0,0.88)',
        display: 'flex',
        flexDirection: 'column',
        padding: '12px',
      }}
    >
      <Box
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          marginBottom: '8px',
        }}
      >
        <Box bold fontSize="1.1em" style={{ marginRight: 'auto' }}>
          Choose a Species
        </Box>
        <Input
          expensive
          placeholder="Search…"
          value={search}
          onChange={(v) => setSearch(v)}
          width="240px"
        />
        <Button icon="xmark" color="bad" onClick={onClose}>
          Close
        </Button>
      </Box>
      <Box
        style={{
          flex: 1,
          minHeight: 0,
          overflowY: 'auto',
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
          gap: '10px',
          alignContent: 'start',
        }}
      >
        {filteredEntries.map(([key, meta]) => (
          <SpeciesCard
            key={key}
            isSelected={key === currentKey}
            isSynthetic={key.startsWith('_')}
            meta={meta}
            onPick={() => onPick(key)}
          />
        ))}
      </Box>
    </Box>
  );
};

const SpeciesCard = ({
  meta,
  isSelected,
  isSynthetic,
  onPick,
}: {
  meta: SpeciesMeta;
  isSelected: boolean;
  isSynthetic: boolean;
  onPick: () => void;
}) => {
  const [showDetails, setShowDetails] = useState(false);
  return (
    <Box
      style={{
        padding: '8px 10px',
        borderRadius: '4px',
        background: isSelected
          ? 'rgba(52,152,219,0.22)'
          : isSynthetic
            ? 'rgba(155,89,182,0.16)'
            : 'rgba(255,255,255,0.04)',
        border: isSelected
          ? '1px solid rgba(52,152,219,0.7)'
          : isSynthetic
            ? '1px solid rgba(155,89,182,0.55)'
            : '1px solid rgba(255,255,255,0.08)',
        display: 'flex',
        flexDirection: 'column',
        gap: '6px',
      }}
    >
      <Box
        style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}
        onClick={onPick}
      >
        {meta.thumb_b64 && (
          <Box style={{ flex: '0 0 auto' }}>
            <img
              src={`data:image/png;base64,${meta.thumb_b64}`}
              alt=""
              width={64}
              height={64}
              style={{ imageRendering: 'pixelated' }}
            />
          </Box>
        )}
        <Box style={{ flex: 1, minWidth: 0 }}>
          <Box bold fontSize="1em">
            {meta.name}
            {isSynthetic && (
              <Box
                inline
                color="label"
                fontSize="0.7em"
                ml={0.5}
                style={{ verticalAlign: 'middle' }}
              >
                (synthetic)
              </Box>
            )}
          </Box>
          {meta.pitch && (
            <Box color="label" fontSize="0.8em" style={{ marginTop: '2px' }}>
              {meta.pitch}
            </Box>
          )}
        </Box>
      </Box>
      <Box
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '6px',
        }}
      >
        <Button
          compact
          icon={isSelected ? 'check' : undefined}
          color={isSelected ? 'good' : undefined}
          onClick={onPick}
        >
          {isSelected ? 'Selected' : 'Pick'}
        </Button>
        <Button
          compact
          icon={showDetails ? 'chevron-up' : 'circle-info'}
          onClick={() => setShowDetails((v) => !v)}
        >
          {showDetails ? 'Hide details' : 'Details'}
        </Button>
      </Box>
      {showDetails && meta.blurb && (
        <Box
          style={{
            background: 'rgba(0,0,0,0.25)',
            border: '1px solid rgba(255,255,255,0.06)',
            borderRadius: '3px',
            padding: '6px 8px',
            maxHeight: '160px',
            overflowY: 'auto',
            fontSize: '0.85em',
            lineHeight: '1.35',
          }}
        >
          {/* Species blurbs are server-authored markup (span_italics,
              span_bold, etc.). Route through the sanitizing HtmlRenderer
              instead of dangerouslySetInnerHTML. */}
          <HtmlRenderer html={meta.blurb} />
        </Box>
      )}
    </Box>
  );
};
