// DQAdd — Body markings as layers. The list is the draw order (top of the list is drawn first,
// so later layers paint over earlier ones): each layer has a thumbnail, the body parts it covers
// as chips (click one to show/hide the marking there), its colour (palette first), a visibility
// toggle, reorder buttons and per-part colours. The picker is searchable, previews the marking
// on the body together with the character's current layers, and lists only the markings the
// character's species can wear unless "all species" is ticked.
//
// On the Looks tab the editor can be scoped to a body region (`zones`): it then lists only the
// layers and candidates that touch those body parts.

import { useMemo, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { getIconFromRefMap } from 'tgui/events/handlers/assets';
import { Box, Button, Input, Section } from 'tgui-core/components';
import { ColorSwatch } from '../colors';
import { Switch } from '../controls';
import { ColorizedImage, getImage } from '../helper_components';
import type { EditorProps } from './index';

type ZoneState = { color: string; on: number };
type MarkingState = Record<string, ZoneState | string>;
type MarkingsData = {
  markings: Record<string, MarkingState>;
  /// Marking names the current species cannot wear (the picker hides them by default).
  incompatible?: string[];
  species?: string;
};
type MarkingStyleMeta = {
  name: string;
  body_parts: string[];
  icon?: string;
  icon_state?: string;
};
type MarkingStatic = {
  available_styles: Record<string, MarkingStyleMeta>;
};

const ZONE_LABELS: Record<string, string> = {
  head: 'Head',
  torso: 'Chest',
  groin: 'Groin',
  l_arm: 'L arm',
  r_arm: 'R arm',
  l_hand: 'L hand',
  r_hand: 'R hand',
  l_leg: 'L leg',
  r_leg: 'R leg',
  l_foot: 'L foot',
  r_foot: 'R foot',
};

const send = (
  act: ReturnType<typeof useBackend>['act'],
  action: string,
  params: Record<string, unknown>,
) => act('dq_editor_action', { editor: 'body_markings', action, params });

const zonesOf = (state: MarkingState) =>
  Object.entries(state).filter(
    (e): e is [string, ZoneState] =>
      !!e[1] && typeof e[1] === 'object' && 'on' in e[1],
  );

/// Draws a human silhouette behind a marking sprite.
const humanBackground = async (ctx: OffscreenCanvasRenderingContext2D) => {
  ctx.save();
  ctx.globalCompositeOperation = 'destination-over';
  const iconRef = getIconFromRefMap('icons/mob/human.dmi');
  if (!iconRef) {
    ctx.restore();
    return;
  }
  try {
    const background = await getImage(`${iconRef}?state=body_m_s&dir=2`);
    ctx.drawImage(background, 0, 0, ctx.canvas.width, ctx.canvas.height);
  } catch {
    // no silhouette available (e.g. the asset is not loaded): the sprite alone
  }
  ctx.restore();
};

/// body_parts should be a list of organ tags; an older server could send a zone -> state table.
const normalizeStyles = (raw: Record<string, MarkingStyleMeta>) => {
  const out: Record<string, MarkingStyleMeta> = {};
  for (const [key, meta] of Object.entries(raw)) {
    const parts: unknown = meta.body_parts;
    out[key] = {
      ...meta,
      body_parts: Array.isArray(parts)
        ? parts
        : Object.keys((parts as object) ?? {}).filter((k) => k !== 'color'),
    };
  }
  return out;
};

export const BodyMarkingsEditor = ({
  data,
  staticData,
  zones,
  zoneLabel,
}: EditorProps & { zones?: string[]; zoneLabel?: string }) => {
  const { act } = useBackend();
  const d = data as MarkingsData;
  const rawStyles = ((staticData ?? {}) as MarkingStatic).available_styles;
  const styles = useMemo(() => normalizeStyles(rawStyles ?? {}), [rawStyles]);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);

  const touches = (key: string) =>
    !zones || (styles[key]?.body_parts ?? []).some((z) => zones.includes(z));
  const layers = Object.entries(d.markings ?? {});
  const shown = layers.filter(([key]) => touches(key));

  return (
    <Section
      title={zoneLabel ? `Markings: ${zoneLabel}` : 'Body Markings'}
      buttons={
        <Button
          icon={pickerOpen ? 'xmark' : 'plus'}
          selected={pickerOpen}
          onClick={() => setPickerOpen((v) => !v)}
        >
          {pickerOpen ? 'Close picker' : 'Add marking'}
        </Button>
      }
    >
      {pickerOpen && (
        <MarkingPicker
          styles={styles}
          layers={layers}
          incompatible={d.incompatible ?? []}
          species={d.species}
          zones={zones}
          onAdd={(key) => {
            send(act, 'add', { marking: key });
            setPickerOpen(false);
          }}
        />
      )}
      {shown.length === 0 && !pickerOpen && (
        <Box italic color="label">
          {layers.length && zones
            ? `No markings on the ${zoneLabel?.toLowerCase() ?? 'region'}; ${layers.length} elsewhere.`
            : 'No markings yet. "Add marking" opens the picker.'}
        </Box>
      )}
      <Box style={{ display: 'flex', flexDirection: 'column', gap: '0.3em' }}>
        {shown.map(([key, state]) => (
          <MarkingLayer
            key={key}
            markingKey={key}
            state={state}
            meta={styles[key]}
            index={layers.findIndex(([k]) => k === key)}
            count={layers.length}
            expanded={expanded === key}
            onExpand={() => setExpanded(expanded === key ? null : key)}
          />
        ))}
      </Box>
    </Section>
  );
};

const MarkingLayer = ({
  markingKey,
  state,
  meta,
  index,
  count,
  expanded,
  onExpand,
}: {
  markingKey: string;
  state: MarkingState;
  meta?: MarkingStyleMeta;
  index: number;
  count: number;
  expanded: boolean;
  onExpand: () => void;
}) => {
  const { act } = useBackend();
  const zones = zonesOf(state);
  const anyOn = zones.some(([, z]) => !!z.on);
  const color =
    (typeof state.color === 'string' ? state.color : null) ??
    zones[0]?.[1].color ??
    '#ffffff';
  return (
    <Box
      style={{
        background: 'rgba(255,255,255,0.04)',
        borderRadius: '0.3em',
        padding: '0.3em',
        opacity: anyOn ? 1 : 0.55,
      }}
    >
      <Box
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '0.5em',
          flexWrap: 'wrap',
        }}
      >
        <Box style={{ flex: '0 0 auto' }}>
          {meta?.icon && meta.icon_state ? (
            <ColorizedImage
              iconRef={meta.icon}
              iconState={meta.icon_state}
              color={color}
              postRender={humanBackground}
              size={48}
            />
          ) : (
            <span
              style={{
                display: 'inline-block',
                width: '2.5em',
                height: '2.5em',
                background: color,
                borderRadius: '0.3em',
              }}
            />
          )}
        </Box>
        <Box style={{ flex: '1 1 10em', minWidth: 0 }}>
          <Box bold style={{ overflowWrap: 'anywhere' }}>
            {meta?.name ?? markingKey}
          </Box>
          <Box
            style={{
              display: 'flex',
              flexWrap: 'wrap',
              gap: '0.2em',
              marginTop: '0.2em',
            }}
          >
            {zones.map(([zone, z]) => (
              <Button
                key={zone}
                compact
                selected={!!z.on}
                tooltip={`${z.on ? 'Hide' : 'Show'} on ${ZONE_LABELS[zone] ?? zone}`}
                onClick={() =>
                  send(act, 'toggle_zone', { marking: markingKey, zone })
                }
              >
                {ZONE_LABELS[zone] ?? zone}
              </Button>
            ))}
          </Box>
        </Box>
        <Box
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '0.3em',
            flexWrap: 'wrap',
          }}
        >
          <ColorSwatch
            color={color}
            label="Colour"
            onPick={(hex) =>
              send(act, 'set_color_value', { marking: markingKey, color: hex })
            }
            onCustom={() => send(act, 'set_color', { marking: markingKey })}
          />
          <Switch
            checked={anyOn}
            label={anyOn ? 'Visible' : 'Hidden'}
            onToggle={() =>
              send(act, 'toggle_all', {
                marking: markingKey,
                on: anyOn ? 0 : 1,
              })
            }
          />
          <Button
            icon="arrow-up"
            disabled={index <= 0}
            tooltip="Draw earlier (under the layers below)"
            onClick={() => send(act, 'move_up', { marking: markingKey })}
          />
          <Button
            icon="arrow-down"
            disabled={index >= count - 1}
            tooltip="Draw later (over the layers above)"
            onClick={() => send(act, 'move_down', { marking: markingKey })}
          />
          <Button
            icon="sliders"
            selected={expanded}
            tooltip="Colour per body part"
            onClick={onExpand}
          />
          <Button.Confirm
            icon="trash"
            color="bad"
            tooltip="Remove"
            onClick={() => send(act, 'remove', { marking: markingKey })}
          />
        </Box>
      </Box>
      {expanded && (
        <Box
          mt={0.4}
          style={{
            display: 'grid',
            gridTemplateColumns:
              'repeat(auto-fill, minmax(min(100%, 9em), 1fr))',
            gap: '0.3em',
          }}
        >
          {zones.map(([zone, z]) => (
            <Box
              key={zone}
              style={{ display: 'flex', alignItems: 'center', gap: '0.3em' }}
            >
              <ColorSwatch
                color={z.color}
                label={ZONE_LABELS[zone] ?? zone}
                onPick={(hex) =>
                  send(act, 'set_color_value', {
                    marking: markingKey,
                    zone,
                    color: hex,
                  })
                }
                onCustom={() =>
                  send(act, 'set_zone_color', { marking: markingKey, zone })
                }
              />
              <Box color={z.on ? undefined : 'label'}>
                {ZONE_LABELS[zone] ?? zone}
              </Box>
            </Box>
          ))}
        </Box>
      )}
    </Box>
  );
};

const PREVIEW_SIZE = 128;

const MarkingPicker = ({
  styles,
  layers,
  incompatible,
  species,
  zones,
  onAdd,
}: {
  styles: Record<string, MarkingStyleMeta>;
  layers: Array<[string, MarkingState]>;
  incompatible: string[];
  species?: string;
  zones?: string[];
  onAdd: (key: string) => void;
}) => {
  const [search, setSearch] = useState('');
  const [allSpecies, setAllSpecies] = useState(false);
  const [hovered, setHovered] = useState<string | null>(null);
  const used = new Set(layers.map(([k]) => k));
  const blocked = new Set(incompatible);
  const lc = search.trim().toLowerCase();
  const candidates = Object.entries(styles)
    .filter(([key, meta]) => {
      if (used.has(key)) return false;
      if (!allSpecies && blocked.has(key)) return false;
      if (zones && !meta.body_parts.some((z) => zones.includes(z)))
        return false;
      if (!lc) return true;
      return (
        meta.name.toLowerCase().includes(lc) ||
        meta.body_parts.some((z) =>
          (ZONE_LABELS[z] ?? z).toLowerCase().includes(lc),
        )
      );
    })
    .sort((a, b) => a[1].name.localeCompare(b[1].name));
  const previewKey = hovered && styles[hovered] ? hovered : null;
  return (
    <Box
      mb={0.6}
      p={0.5}
      style={{
        border: '0.0833em solid rgba(255,255,255,0.15)',
        borderRadius: '0.3em',
        background: 'rgba(0,0,0,0.25)',
        display: 'flex',
        gap: '0.6em',
        flexWrap: 'wrap',
      }}
    >
      <Box style={{ flex: '0 0 auto', textAlign: 'center' }}>
        <MarkingPreview
          layers={layers}
          styles={styles}
          candidate={previewKey}
        />
        <Box color="label" fontSize="0.85em" style={{ maxWidth: '10.7em' }}>
          {previewKey
            ? styles[previewKey].name
            : 'Point at a marking to try it on'}
        </Box>
      </Box>
      <Box style={{ flex: '1 1 16em', minWidth: 0 }}>
        <Box
          style={{
            display: 'flex',
            gap: '0.5em',
            alignItems: 'center',
            flexWrap: 'wrap',
          }}
          mb={0.4}
        >
          <Box style={{ flex: '1 1 10em' }}>
            <Input
              fluid
              autoFocus
              expensive
              placeholder="Search markings or body parts…"
              value={search}
              onChange={setSearch}
            />
          </Box>
          <Switch
            checked={allSpecies}
            label={`All species${incompatible.length ? ` (+${incompatible.length})` : ''}`}
            tooltip={
              species
                ? `Off: only markings a ${species} can wear.`
                : 'Off: only markings this species can wear.'
            }
            onToggle={() => setAllSpecies((v) => !v)}
          />
        </Box>
        <Box color="label" fontSize="0.85em" mb={0.3}>
          {candidates.length} marking{candidates.length === 1 ? '' : 's'}
        </Box>
        <Box
          style={{
            maxHeight: '20em',
            overflowY: 'auto',
            display: 'grid',
            gridTemplateColumns:
              'repeat(auto-fill, minmax(min(100%, 12em), 1fr))',
            gap: '0.25em',
          }}
          onMouseLeave={() => setHovered(null)}
        >
          {candidates.map(([key, meta]) => (
            <Button
              key={key}
              color={blocked.has(key) ? 'average' : 'transparent'}
              tooltip={
                blocked.has(key)
                  ? `${meta.name}: not made for this species`
                  : meta.name
              }
              onMouseEnter={() => setHovered(key)}
              onClick={() => onAdd(key)}
            >
              <Box
                style={{ display: 'flex', alignItems: 'center', gap: '0.3em' }}
              >
                {meta.icon && meta.icon_state ? (
                  <ColorizedImage
                    iconRef={meta.icon}
                    iconState={meta.icon_state}
                    color="#ffffff"
                    size={32}
                  />
                ) : null}
                <Box
                  style={{
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                    minWidth: 0,
                  }}
                >
                  {meta.name}
                </Box>
              </Box>
            </Button>
          ))}
        </Box>
      </Box>
    </Box>
  );
};

/// The silhouette with the character's visible layers, plus the candidate on top (white).
const MarkingPreview = ({
  layers,
  styles,
  candidate,
}: {
  layers: Array<[string, MarkingState]>;
  styles: Record<string, MarkingStyleMeta>;
  candidate: string | null;
}) => {
  const visible = layers.filter(([, state]) =>
    zonesOf(state).some(([, z]) => !!z.on),
  );
  const stack: Array<[string, string]> = visible.map(([key, state]) => [
    key,
    (typeof state.color === 'string' ? state.color : null) ??
      zonesOf(state)[0]?.[1].color ??
      '#ffffff',
  ]);
  if (candidate) stack.push([candidate, '#ffffff']);
  const layer = { position: 'absolute' as const, inset: 0 };
  return (
    <Box
      style={{
        position: 'relative',
        width: `${PREVIEW_SIZE / 12}em`,
        height: `${PREVIEW_SIZE / 12}em`,
        background: 'rgba(255,255,255,0.05)',
        borderRadius: '0.3em',
      }}
    >
      <Box style={layer}>
        <SilhouetteImage />
      </Box>
      {stack.map(([key, color]) => {
        const meta = styles[key];
        if (!meta?.icon || !meta.icon_state) return null;
        return (
          <Box key={key} style={layer}>
            <ColorizedImage
              iconRef={meta.icon}
              iconState={meta.icon_state}
              color={color}
              size={PREVIEW_SIZE}
            />
          </Box>
        );
      })}
    </Box>
  );
};

const SilhouetteImage = () => {
  const iconRef = getIconFromRefMap('icons/mob/human.dmi');
  if (!iconRef) return null;
  return (
    <img
      src={`${iconRef}?state=body_m_s&dir=2`}
      alt=""
      width={PREVIEW_SIZE}
      height={PREVIEW_SIZE}
      style={{ imageRendering: 'pixelated', width: '100%', height: '100%' }}
    />
  );
};
