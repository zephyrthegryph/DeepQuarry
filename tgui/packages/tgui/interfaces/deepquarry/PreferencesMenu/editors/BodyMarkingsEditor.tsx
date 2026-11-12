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
import type {
  PrefEditorBodyMarkings,
  PrefEditorBodyMarkingsStatic,
} from '../../../generated/_schemas';
import { ColorChoice } from '../colors';
import { Switch } from '../controls';
import { ColorizedImage, getImage } from '../helper_components';
import type { EditorProps } from './index';
import {
  MARKING_CATEGORIES,
  type MarkingCategory,
  markingCategory,
  markingSubgroup,
} from './markingCategories';

type MarkingsData = PrefEditorBodyMarkings;
type MarkingState = MarkingsData['markings'][string];
type ZoneState = Extract<MarkingState[string], { on: number }>;
type MarkingStyleMeta =
  PrefEditorBodyMarkingsStatic['available_styles'][string];

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
  data: d,
  staticData,
  zones,
  zoneLabel,
}: EditorProps<'body_markings'> & { zones?: string[]; zoneLabel?: string }) => {
  const { act } = useBackend();
  const rawStyles = staticData?.available_styles;
  const styles = useMemo(() => normalizeStyles(rawStyles ?? {}), [rawStyles]);
  const [expanded, setExpanded] = useState<string | null>(null);

  const touches = (key: string) =>
    !zones || (styles[key]?.body_parts ?? []).some((z) => zones.includes(z));
  const layers = Object.entries(d.markings ?? {});
  const allLinks = d.links ?? {};
  const shown = layers.filter(([key]) => touches(key));

  return (
    <Section title={zoneLabel ? `Markings: ${zoneLabel}` : 'Markings'}>
      <Box bold color="label" mb={0.2}>
        On this character ({layers.length})
      </Box>
      {shown.length === 0 && (
        <Box italic color="label" mb={0.3}>
          {layers.length && zones
            ? `No markings on the ${zoneLabel?.toLowerCase() ?? 'region'}; ${layers.length} elsewhere.`
            : 'No markings yet. Pick one from the list below.'}
        </Box>
      )}
      <Box
        mb={0.6}
        style={{ display: 'flex', flexDirection: 'column', gap: '0.3em' }}
      >
        {shown.map(([key, state]) => (
          <MarkingLayer
            key={key}
            markingKey={key}
            state={state}
            links={allLinks[key]}
            meta={styles[key]}
            index={layers.findIndex(([k]) => k === key)}
            count={layers.length}
            expanded={expanded === key}
            onExpand={() => setExpanded(expanded === key ? null : key)}
          />
        ))}
      </Box>
      <MarkingPicker
        styles={styles}
        layers={layers}
        incompatible={d.incompatible ?? []}
        species={d.species ?? undefined}
        zones={zones}
        onAdd={(key) => send(act, 'add', { marking: key })}
      />
    </Section>
  );
};

const MarkingLayer = ({
  markingKey,
  state,
  links,
  meta,
  index,
  count,
  expanded,
  onExpand,
}: {
  markingKey: string;
  state: MarkingState;
  /// Zone (or "color", the whole marking) -> the palette slot it links to.
  links?: Record<string, string>;
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
          <ColorChoice
            color={color}
            link={links?.color}
            onLink={(slot) =>
              send(act, 'set_color_value', { marking: markingKey, color: slot })
            }
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
              <ColorChoice
                color={z.color}
                link={links?.[zone]}
                label={ZONE_LABELS[zone] ?? zone}
                category="other"
                onLink={(slot) =>
                  send(act, 'set_color_value', {
                    marking: markingKey,
                    zone,
                    color: slot,
                  })
                }
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
            </Box>
          ))}
        </Box>
      )}
    </Box>
  );
};

const PREVIEW_SIZE = 128;

/// The abstract base types' name (DEVELOPER_WARNING_NAME): never a real marking.
const DEVELOPER_NAME = 'you should not see this...';

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
  const [category, setCategory] = useState<MarkingCategory>('Full body');
  const used = new Set(layers.map(([k]) => k));
  const blocked = new Set(incompatible);
  const lc = search.trim().toLowerCase();
  // Classified once per catalog, not on every server update.
  const catalog = useMemo(
    () =>
      Object.entries(styles)
        .filter(([, meta]) => meta.name !== DEVELOPER_NAME)
        .map(([key, meta]) => {
          const cat = markingCategory(meta.name, meta.body_parts);
          return {
            key,
            meta,
            category: cat,
            group: markingSubgroup(cat, meta.name, meta.body_parts),
          };
        })
        .sort(
          (a, b) =>
            a.group.localeCompare(b.group) ||
            a.meta.name.localeCompare(b.meta.name),
        ),
    [styles],
  );
  const candidates = catalog.filter(({ key, meta }) => {
    if (used.has(key)) return false;
    if (!allSpecies && blocked.has(key)) return false;
    if (zones && !meta.body_parts.some((z) => zones.includes(z))) return false;
    if (!lc) return true;
    return (
      meta.name.toLowerCase().includes(lc) ||
      meta.body_parts.some((z) =>
        (ZONE_LABELS[z] ?? z).toLowerCase().includes(lc),
      )
    );
  });
  const counts = new Map<MarkingCategory, number>();
  for (const c of candidates) {
    counts.set(c.category, (counts.get(c.category) ?? 0) + 1);
  }
  // A search looks everywhere; otherwise one category, so a few dozen sprites mount instead of all of them.
  const shown = lc
    ? [...candidates].sort((a, b) => a.meta.name.localeCompare(b.meta.name))
    : candidates.filter((c) => c.category === category);
  const previewKey = hovered && styles[hovered] ? hovered : null;
  let lastGroup = '';
  return (
    <Box
      p={0.5}
      style={{
        border: '0.0833em solid rgba(255,255,255,0.15)',
        borderRadius: '0.3em',
        background: 'rgba(0,0,0,0.25)',
      }}
    >
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
      <Box style={{ display: 'flex', gap: '0.5em', flexWrap: 'wrap' }}>
        <Box
          style={{
            flex: '0 0 12em',
            display: 'flex',
            flexDirection: 'column',
            gap: '0.1em',
            opacity: lc ? 0.5 : 1,
          }}
        >
          {MARKING_CATEGORIES.filter((c) => counts.has(c)).map((c) => (
            <Button
              key={c}
              fluid
              selected={!lc && c === category}
              onClick={() => {
                setSearch('');
                setCategory(c);
              }}
            >
              <Box style={{ display: 'flex' }}>
                <Box style={{ flex: 1 }}>{c}</Box>
                <Box>{counts.get(c)}</Box>
              </Box>
            </Button>
          ))}
        </Box>
        <Box
          style={{
            flex: '1 1 16em',
            minWidth: 0,
            height: '26em',
            overflowY: 'auto',
          }}
          onMouseLeave={() => setHovered(null)}
        >
          {shown.length === 0 && (
            <Box italic color="label" p={0.3}>
              No markings match.
            </Box>
          )}
          {shown.map(({ key, meta, group }) => {
            const header = !lc && group && group !== lastGroup ? group : null;
            if (header) lastGroup = group;
            const parts = meta.body_parts.length;
            return (
              <Box key={key}>
                {header && (
                  <Box bold color="label" mt={0.3} mb={0.1}>
                    {header}
                  </Box>
                )}
                <Button
                  fluid
                  color={blocked.has(key) ? 'average' : 'transparent'}
                  tooltip={
                    blocked.has(key) ? 'Not made for this species' : undefined
                  }
                  onMouseEnter={() => setHovered(key)}
                  onClick={() => onAdd(key)}
                >
                  <Box
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: '0.4em',
                    }}
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
                        flex: 1,
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap',
                        minWidth: 0,
                      }}
                    >
                      {meta.name}
                    </Box>
                    <Box color="label" fontSize="0.85em">
                      {parts === 1
                        ? (ZONE_LABELS[meta.body_parts[0]] ??
                          meta.body_parts[0])
                        : `${parts} parts`}
                    </Box>
                  </Box>
                </Button>
              </Box>
            );
          })}
        </Box>
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
