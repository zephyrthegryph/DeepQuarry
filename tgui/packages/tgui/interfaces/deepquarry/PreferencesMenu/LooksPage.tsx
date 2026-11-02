// The Looks tab: two categories in the left column (with the body doll, the preview switches and the palette).
// Body & markings is one window of sections (skin, hair, ears, tail, wings, legs, anything no card claims), with
// the markings selector below them; Limbs & organs is its own. Ears, tail and wings show their style picker while absent.

import { type ReactNode, useContext, useEffect, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Box, Button, Section } from 'tgui-core/components';
import { type DollRegion, ZoneDoll } from '../shared/ZoneDoll';
import { WidgetGrid } from './CategoryPage';
import {
  ColorStrip,
  PALETTE_SLOTS,
  PaletteSlots,
  type StripColor,
} from './colors';
import { Switch } from './controls';
import { getEditor } from './editors';
import { BodyMarkingsEditor } from './editors/BodyMarkingsEditor';
import { OrgansEditor } from './editors/OrgansEditor';
import { labelForGroup } from './labels';
import { PrefWidget } from './PrefWidget';
import {
  editorAnchor,
  groupAnchor,
  highlightStyle,
  prefAnchor,
  SearchHighlightContext,
  useSearchHighlight,
} from './search';
import type { PrefCategory, PrefWidgetItem } from './types';

export type Region = 'body' | 'organs';

const REGION_LABELS: Record<Region, string> = {
  body: 'Body & markings',
  organs: 'Limbs & organs',
};

/// Doll groups, and the marking filter each sets (organ tags, BP_*).
const ZONE_GROUPS: Array<{ label: string; zones: string[] }> = [
  { label: 'Head', zones: ['head'] },
  { label: 'Torso', zones: ['torso', 'groin'] },
  { label: 'Arms', zones: ['l_arm', 'r_arm'] },
  { label: 'Legs', zones: ['l_leg', 'r_leg'] },
  { label: 'Hands & feet', zones: ['l_hand', 'r_hand', 'l_foot', 'r_foot'] },
];
const zoneGroup = (zone: string) =>
  ZONE_GROUPS.find((g) =>
    g.zones.includes(zone === 'eyes' || zone === 'mouth' ? 'head' : zone),
  ) ?? null;

type CardId =
  | 'skin'
  | 'eyes'
  | 'hair'
  | 'ears'
  | 'tail'
  | 'wings'
  | 'legs'
  | 'markings'
  | 'organs'
  | 'chassis';

export const REGION_CARDS: Record<Region, CardId[]> = {
  body: [
    'chassis',
    'skin',
    'eyes',
    'hair',
    'ears',
    'tail',
    'wings',
    'legs',
    'markings',
  ],
  organs: ['organs'],
};

/// The prefs and editors each card owns (anything else lands in "Other").
const CARD_KEYS: Record<CardId, string[]> = {
  skin: ['skin_color'],
  eyes: ['eyes_color'],
  hair: [
    'hair_style_name',
    'facial_style_name',
    'grad_style_name',
    'hair_color',
    'facial_color',
    'grad_color',
  ],
  ears: [
    'ear_style',
    'ear_secondary_style',
    'ears_color1',
    'ears_color2',
    'ears_color3',
    'ears_alpha',
    'secondary_ears_alpha',
  ],
  tail: [
    'tail_style',
    'tail_color1',
    'tail_color2',
    'tail_color3',
    'tail_alpha',
  ],
  wings: [
    'wing_style',
    'wing_color1',
    'wing_color2',
    'wing_color3',
    'wing_alpha',
  ],
  legs: ['digitigrade'],
  markings: ['body_markings'],
  organs: ['organs'],
  chassis: ['robot_chassis'],
};

const KEY_TO_CARD: Record<string, CardId> = {};
for (const [card, keys] of Object.entries(CARD_KEYS)) {
  for (const key of keys) KEY_TO_CARD[key] = card as CardId;
}

/// The one category that shows a card.
const cardRegion = (card: CardId): Region =>
  (Object.keys(REGION_CARDS) as Region[]).find((r) =>
    REGION_CARDS[r].includes(card),
  ) ?? 'body';

const LEFT_COLUMN_KEYS = [
  'palette_primary',
  'palette_secondary',
  'palette_tertiary',
  'palette_extra1',
  'palette_extra2',
  'preview_loadout',
  'preview_job',
  'animations_toggle',
];
const LEFT_COLUMN_GROUPS = ['palette', 'preview'];

/// Where a search jump lands: the category holding it, or null when it stays put (the left column is always shown).
export const regionForHighlight = (highlight: string): Region | null => {
  if (highlight.startsWith('group:')) {
    const group = highlight.slice(highlight.indexOf('/') + 1);
    if (LEFT_COLUMN_GROUPS.includes(group)) return null;
    return group === 'organs' ? 'organs' : 'body';
  }
  const key = highlight.replace(/^(pref|editor):/, '');
  if (LEFT_COLUMN_KEYS.includes(key)) return null;
  const card = KEY_TO_CARD[key];
  return card ? cardRegion(card) : 'body';
};

/// The body layout fits a page with body parts (human mode); robot and pAI pages, which have
/// none of these, keep the plain group list.
export const looksHasBody = (page: PrefCategory) =>
  page.groups.some((g) =>
    g.items.some((i) =>
      ['skin_color', 'hair_style_name', 'tail_style', 'body_markings'].includes(
        i.key,
      ),
    ),
  );

/// Remembered across tab switches (the page remounts).
let rememberedRegion: Region = 'body';

const PREVIEW_KEYS = ['preview_loadout', 'preview_job', 'animations_toggle'];

/// A hair style that draws nothing: its colours mean nothing either.
const isNoHair = (value: unknown) =>
  isNoStyle(value) ||
  ['bald', 'shaved'].includes(String(value).trim().toLowerCase());

const isNoStyle = (value: unknown) => {
  const s = String(value ?? '')
    .trim()
    .toLowerCase();
  return s === '' || s === 'none' || s === 'null';
};

type Props = {
  page: PrefCategory;
  staticData?: Record<string, Record<string, unknown>>;
  values: Record<string, unknown>;
  editorData: Record<string, Record<string, unknown>>;
};

export const LooksPage = ({ page, staticData, values, editorData }: Props) => {
  const [region, setRegionState] = useState<Region>(rememberedRegion);
  const setRegion = (r: Region) => {
    rememberedRegion = r;
    setRegionState(r);
  };

  // Index what the server sent: widgets by key, editors by key, and the groups they came from.
  const widgets: Record<string, PrefWidgetItem> = {};
  const editors = new Set<string>();
  const groupOf: Record<string, string> = {};
  for (const group of page.groups) {
    for (const item of group.items) {
      groupOf[item.key] = group.group;
      if (item.type === 'widget') {
        if (item.widget !== 'hidden') widgets[item.key] = item;
      } else {
        editors.add(item.key);
      }
    }
  }
  const has = (key: string) => !!widgets[key] || editors.has(key);
  const withValue = (key: string): PrefWidgetItem | null => {
    const item = widgets[key];
    if (!item) return null;
    return {
      ...item,
      value: Object.hasOwn(values, key) ? values[key] : item.value,
    };
  };

  // A search jump to a field the current region hides switches to a region that shows it.
  const highlight = useContext(SearchHighlightContext);
  const [focusLimb, setFocusLimb] = useState<string | null>(null);
  const [markingZones, setMarkingZones] = useState<
    (typeof ZONE_GROUPS)[number] | null
  >(null);
  useEffect(() => {
    if (!highlight) return;
    const target = regionForHighlight(highlight);
    if (!target) return;
    if (highlight === 'editor:body_markings') setMarkingZones(null);
    setRegion(target);
  }, [highlight]);

  // Cards that have something to show in this play mode.
  const cardHasContent = (card: CardId) => CARD_KEYS[card].some(has);
  const claimed = new Set(
    [
      ...Object.values(CARD_KEYS).flat(),
      ...PALETTE_SLOTS.map((p) => p.prefKey),
      ...PREVIEW_KEYS,
    ].filter((k) => has(k)),
  );
  const otherGroups = page.groups
    .map((group) => ({
      ...group,
      items: group.items.filter(
        (item) =>
          !claimed.has(item.key) &&
          !(item.type === 'widget' && item.widget === 'hidden'),
      ),
    }))
    .filter((group) => group.items.length > 0);

  const zones = markingZones?.zones;
  const shownRegion = region;
  const cards = REGION_CARDS[shownRegion].filter(cardHasContent);

  const renderCard = (card: CardId) => {
    switch (card) {
      case 'skin':
        return (
          <PartCard key={card} title="Skin" anchorGroup={groupOf.skin_color}>
            {values.species_has_skin_color !== 0 && (
              <ColorStrip
                colors={pick(widgets, [['skin_color', 'Skin']])}
                values={values}
              />
            )}
          </PartCard>
        );
      case 'eyes':
        return (
          <PartCard key={card} title="Eyes">
            <ColorStrip
              colors={pick(widgets, [['eyes_color', 'Eyes']])}
              values={values}
            />
          </PartCard>
        );
      case 'hair':
        return (
          <PartCard key={card} title="Hair" anchorGroup="hair">
            <Fields
              keys={['hair_style_name', 'facial_style_name', 'grad_style_name']}
              withValue={withValue}
            />
            <Box mt={0.4}>
              <ColorStrip
                colors={pick(
                  widgets,
                  [
                    isNoHair(values.hair_style_name)
                      ? null
                      : ['hair_color', 'Hair'],
                    isNoHair(values.facial_style_name)
                      ? null
                      : ['facial_color', 'Facial'],
                    // The gradient colour only matters with a gradient.
                    isNoStyle(values.grad_style_name)
                      ? null
                      : ['grad_color', 'Gradient'],
                  ].filter(Boolean) as Array<[string, string]>,
                )}
                values={values}
              />
            </Box>
          </PartCard>
        );
      case 'ears':
        return (
          <OptionalPart
            key={card}
            title="Ears"
            styleKey="ear_style"
            values={values}
            withValue={withValue}
          >
            <Fields
              keys={['ear_style', 'ear_secondary_style']}
              withValue={withValue}
            />
            <Box mt={0.4}>
              <ColorStrip
                colors={pick(widgets, [
                  ['ears_color1', 'Primary'],
                  ['ears_color2', 'Secondary'],
                  ['ears_color3', 'Tertiary'],
                ])}
                alphas={pick(
                  widgets,
                  [
                    ['ears_alpha', 'Opacity'],
                    isNoStyle(values.ear_secondary_style)
                      ? null
                      : ['secondary_ears_alpha', 'Secondary opacity'],
                  ].filter(Boolean) as Array<[string, string]>,
                )}
                values={values}
              />
            </Box>
          </OptionalPart>
        );
      case 'tail':
      case 'wings': {
        const prefix = card === 'tail' ? 'tail' : 'wing';
        return (
          <OptionalPart
            key={card}
            title={card === 'tail' ? 'Tail' : 'Wings'}
            styleKey={`${prefix}_style`}
            values={values}
            withValue={withValue}
          >
            <Fields keys={[`${prefix}_style`]} withValue={withValue} />
            <Box mt={0.4}>
              <ColorStrip
                colors={pick(widgets, [
                  [`${prefix}_color1`, 'Primary'],
                  [`${prefix}_color2`, 'Secondary'],
                  [`${prefix}_color3`, 'Tertiary'],
                ])}
                alphas={pick(widgets, [[`${prefix}_alpha`, 'Opacity']])}
                values={values}
              />
            </Box>
          </OptionalPart>
        );
      }
      case 'legs':
        return (
          <PartCard key={card} title="Legs">
            <Fields keys={['digitigrade']} withValue={withValue} />
          </PartCard>
        );
      case 'markings':
        return (
          <Box key={card} data-dq-anchor={editorAnchor('body_markings')}>
            <BodyMarkingsEditor
              data={editorData.body_markings ?? {}}
              staticData={staticData?.body_markings}
              zones={zones}
              zoneLabel={markingZones?.label}
            />
          </Box>
        );
      case 'organs':
        return (
          <Box key={card} data-dq-anchor={editorAnchor('organs')}>
            <Section title="Limbs & organs">
              <OrgansEditor
                data={editorData.organs ?? {}}
                staticData={staticData?.organs}
                focusLimb={focusLimb}
              />
            </Section>
          </Box>
        );
      case 'chassis': {
        const key = 'robot_chassis';
        const Editor = getEditor(key);
        return (
          <Box key={card} data-dq-anchor={editorAnchor(key)}>
            <Section title="Chassis">
              <Editor
                data={editorData[key] ?? {}}
                staticData={staticData?.[key]}
              />
            </Section>
          </Box>
        );
      }
    }
  };

  return (
    <Box
      style={{
        display: 'flex',
        flexWrap: 'wrap',
        gap: '0.5em',
        alignItems: 'flex-start',
      }}
    >
      <Box
        style={{
          flex: '0 0 15em',
          position: 'sticky',
          top: 0,
          display: 'flex',
          flexDirection: 'column',
          gap: '0.4em',
        }}
      >
        <BodyDiagram
          selected={shownRegion === 'body' ? (markingZones?.zones ?? []) : []}
          caption={
            shownRegion === 'body'
              ? (markingZones?.label ?? 'All markings')
              : REGION_LABELS[shownRegion]
          }
          onPick={(zone) => {
            if (shownRegion === 'organs') {
              setFocusLimb(zone);
            } else {
              const group = zoneGroup(zone);
              setMarkingZones(group === markingZones ? null : group);
              document
                .querySelector(
                  `[data-dq-anchor="${editorAnchor('body_markings')}"]`,
                )
                ?.scrollIntoView({ block: 'start' });
            }
          }}
          regions={(staticData?.organs?.doll_regions as DollRegion[]) ?? []}
        />
        <Box style={{ display: 'flex', flexDirection: 'column', gap: '0.1em' }}>
          {(Object.keys(REGION_LABELS) as Region[])
            .filter((r) => REGION_CARDS[r].some(cardHasContent))
            .map((r) => (
              <Button
                key={r}
                fluid
                selected={shownRegion === r}
                onClick={() => setRegion(r)}
              >
                {REGION_LABELS[r]}
              </Button>
            ))}
        </Box>
        {PREVIEW_KEYS.some(has) && (
          <Section
            title="Preview"
            data-dq-anchor={groupAnchor('appearance', 'preview')}
          >
            <Box
              style={{ display: 'flex', flexDirection: 'column', gap: '0.3em' }}
            >
              {PREVIEW_KEYS.map(withValue)
                .filter((item): item is PrefWidgetItem => !!item)
                .map((item) => (
                  <PreviewSwitch key={item.key} item={item} />
                ))}
            </Box>
          </Section>
        )}
        {has('palette_primary') && (
          <Section
            title="Palette"
            data-dq-anchor={groupAnchor('appearance', 'palette')}
          >
            <PaletteSlots values={values} />
          </Section>
        )}
      </Box>
      <Box
        style={{
          flex: '1 1 24em',
          minWidth: 0,
          display: 'grid',
          gridTemplateColumns:
            shownRegion === 'body'
              ? 'repeat(auto-fill, minmax(min(100%, max(22em, calc(50% - 0.25em))), 1fr))'
              : '1fr',
          gap: '0.5em',
          alignItems: 'start',
        }}
      >
        {cards
          .filter((card) => card !== 'markings')
          .map((card) => {
            const node = renderCard(card);
            const wide =
              card === 'hair' ||
              card === 'organs' ||
              card === 'legs' ||
              card === 'chassis';
            return (
              <Box
                key={card}
                style={wide ? { gridColumn: '1 / -1' } : undefined}
              >
                {node}
              </Box>
            );
          })}
        {shownRegion === 'body' &&
          otherGroups.map((group) => (
            <Box key={`other-${group.group}`} style={{ gridColumn: '1 / -1' }}>
              <Section
                title={group.group ? labelForGroup(group.group) : 'Other'}
                data-dq-anchor={groupAnchor(page.category, group.group)}
              >
                <WidgetGrid
                  widgets={
                    group.items.filter(
                      (i) => i.type === 'widget',
                    ) as PrefWidgetItem[]
                  }
                  values={values}
                />
                {group.items
                  .filter((i) => i.type === 'editor')
                  .map((i) => {
                    const Editor = getEditor(i.key);
                    return (
                      <Box key={i.key} data-dq-anchor={editorAnchor(i.key)}>
                        <Editor
                          data={editorData[i.key] ?? {}}
                          staticData={staticData?.[i.key]}
                        />
                      </Box>
                    );
                  })}
              </Section>
            </Box>
          ))}
        {cards.includes('markings') && (
          <Box style={{ gridColumn: '1 / -1' }}>{renderCard('markings')}</Box>
        )}
      </Box>
    </Box>
  );
};

const PREVIEW_LABELS: Record<string, string> = {
  preview_loadout: 'Show loadout',
  preview_job: 'Show job outfit',
  animations_toggle: 'Animate',
};

const PreviewSwitch = ({ item }: { item: PrefWidgetItem }) => {
  const { act } = useBackend();
  const anchor = prefAnchor(item.key);
  const lit = useSearchHighlight(anchor);
  return (
    <Box data-dq-anchor={anchor} style={highlightStyle(lit)}>
      <Switch
        checked={!!item.value}
        label={PREVIEW_LABELS[item.key] ?? item.label ?? item.key}
        onToggle={() =>
          act('dq_update_preference', { key: item.key, value: !item.value })
        }
      />
    </Box>
  );
};

/// [key, label] pairs for the keys the page actually has.
const pick = (
  widgets: Record<string, PrefWidgetItem>,
  pairs: Array<[string, string]>,
): StripColor[] =>
  pairs.filter(([key]) => widgets[key]).map(([key, label]) => ({ key, label }));

const PartCard = ({
  title,
  children,
  buttons,
  anchorGroup,
}: {
  title: string;
  children: ReactNode;
  buttons?: ReactNode;
  anchorGroup?: string;
}) => {
  const anchor = anchorGroup ? groupAnchor('appearance', anchorGroup) : '';
  const lit = useSearchHighlight(anchor);
  return (
    <Section
      title={title}
      buttons={buttons}
      data-dq-anchor={anchor || undefined}
      style={highlightStyle(!!anchor && lit)}
    >
      {children}
    </Section>
  );
};

/// A label/control list for some of the page's prefs (skipping the ones it lacks).
const Fields = ({
  keys,
  withValue,
  bare,
}: {
  keys: string[];
  withValue: (key: string) => PrefWidgetItem | null;
  bare?: boolean;
}) => {
  const items = keys.map(withValue).filter(Boolean) as PrefWidgetItem[];
  if (!items.length) return null;
  if (bare) {
    return (
      <>
        {items.map((item) => (
          <BareField key={item.key} item={item} />
        ))}
      </>
    );
  }
  const values = Object.fromEntries(items.map((i) => [i.key, i.value]));
  return <WidgetGrid widgets={items} values={values} />;
};

const BareField = ({ item }: { item: PrefWidgetItem }) => {
  const anchor = prefAnchor(item.key);
  const lit = useSearchHighlight(anchor);
  return (
    <Box data-dq-anchor={anchor} style={highlightStyle(lit)}>
      <PrefWidget item={item} />
    </Box>
  );
};

/// Ears, tail and wings: the style picker while the part has none, the full card with Remove after.
const OptionalPart = ({
  title,
  styleKey,
  values,
  withValue,
  children,
}: {
  title: string;
  styleKey: string;
  values: Record<string, unknown>;
  withValue: (key: string) => PrefWidgetItem | null;
  children: ReactNode;
}) => {
  const { act } = useBackend();
  const lowerTitle = title.toLowerCase();
  if (isNoStyle(values[styleKey])) {
    const styleItem = withValue(styleKey);
    return (
      <PartCard title={title}>
        <Box color="label" mb={0.3}>
          This character has no {lowerTitle}. Pick a style to add them.
        </Box>
        {styleItem && <BareField item={styleItem} />}
      </PartCard>
    );
  }
  return (
    <PartCard
      title={title}
      buttons={
        <Button.Confirm
          icon="trash"
          color="transparent"
          tooltip={`Remove the ${lowerTitle}`}
          onClick={() => {
            act('dq_update_preference', { key: styleKey, value: '' });
          }}
        >
          Remove
        </Button.Confirm>
      }
    >
      {children}
    </PartCard>
  );
};

/// The body picker: the HUD's zone-select doll (art and hit areas shared with the game). A part filters the markings, or points at the limb on Limbs & organs.
const BodyDiagram = ({
  selected,
  caption,
  onPick,
  regions,
}: {
  selected: string[];
  caption: string;
  onPick: (zone: string) => void;
  regions: DollRegion[];
}) => {
  const [hover, setHover] = useState<string | null>(null);
  const groupOf = (zone: string) => {
    const group = zoneGroup(zone);
    if (!group) return [zone];
    return group.label === 'Head'
      ? [...group.zones, 'eyes', 'mouth']
      : group.zones;
  };
  return (
    <Box
      style={{
        background: 'rgba(0,0,0,0.25)',
        borderRadius: '0.3em',
        padding: '0.3em',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
      }}
    >
      <ZoneDoll
        size={192}
        regions={regions}
        selected={selected}
        groupOf={groupOf}
        onHover={setHover}
        onPick={onPick}
      />
      <Box textAlign="center" color="label" mt={0.2}>
        {hover ? (zoneGroup(hover)?.label ?? hover) : caption}
      </Box>
    </Box>
  );
};
