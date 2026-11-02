// The Looks tab: two categories in the left column (with the body doll, the preview switches and the palette).
// Body is one table with a row per part (style, its colour channels, options) and the markings selector below it;
// Limbs & organs is its own. Skin and eyes are palette slots. Legs choose among plantigrade, digitigrade and taur:
// a taur is still saved and worn as a tail style, so riding, clothing and vore sprites read what they always did.

import { useContext, useEffect, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Box, Button, Section } from 'tgui-core/components';
import { type DollRegion, ZoneDoll } from '../shared/ZoneDoll';
import { WidgetGrid } from './CategoryPage';
import {
  ColorStrip,
  ColorSwatch,
  normalizeHex,
  PALETTE_SLOTS,
  PaletteSlots,
} from './colors';
import { Switch } from './controls';
import { getEditor } from './editors';
import { BodyMarkingsEditor } from './editors/BodyMarkingsEditor';
import { OrgansEditor } from './editors/OrgansEditor';
import { labelForGroup } from './labels';
import { normalizeChoices, PrefWidget } from './PrefWidget';
import {
  editorAnchor,
  groupAnchor,
  highlightStyle,
  prefAnchor,
  SearchHighlightContext,
  useSearchHighlight,
} from './search';
import type { PrefCategory, PrefThumbnail, PrefWidgetItem } from './types';

export type Region = 'body' | 'organs';

const REGION_LABELS: Record<Region, string> = {
  body: 'Body',
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

type CardId = 'parts' | 'markings' | 'organs' | 'chassis';

export const REGION_CARDS: Record<Region, CardId[]> = {
  body: ['chassis', 'parts', 'markings'],
  organs: ['organs'],
};

/// The prefs and editors each card owns (anything else lands in "Other").
const CARD_KEYS: Record<CardId, string[]> = {
  parts: [
    'skin_color',
    'eyes_color',
    'hair_style_name',
    'facial_style_name',
    'grad_style_name',
    'hair_color',
    'facial_color',
    'grad_color',
    'ear_style',
    'ear_secondary_style',
    'ears_color1',
    'ears_color2',
    'ears_color3',
    'ears_alpha',
    'secondary_ears_alpha',
    'tail_style',
    'tail_color1',
    'tail_color2',
    'tail_color3',
    'tail_alpha',
    'wing_style',
    'wing_color1',
    'wing_color2',
    'wing_color3',
    'wing_alpha',
    'digitigrade',
    'ear_secondary',
  ],
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
      case 'parts':
        return (
          <BodyTable
            key={card}
            values={values}
            widgets={widgets}
            withValue={withValue}
            secondEarColors={
              (editorData.ear_secondary?.colors ?? []) as string[]
            }
            secondEarFallback={
              (editorData.ear_secondary?.fallback ?? []) as string[]
            }
          />
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
              card === 'parts' || card === 'organs' || card === 'chassis';
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

type StyleThumb = { channels?: number; taur?: number };

/// The channels a style draws, from its thumbnail data; a style with no data shows all three.
const channelsOf = (item: PrefWidgetItem | null, value: unknown) => {
  const thumb = item?.thumbnails?.[String(value ?? '')] as
    | StyleThumb
    | undefined;
  return thumb?.channels ?? 3;
};

type PartRow = {
  label: string;
  group: string;
  styleKey: string;
  colors: string[];
  alpha?: string;
  /// A blank style means none, and None offers to clear it.
  clearable?: boolean;
};

const PART_ROWS: PartRow[] = [
  {
    label: 'Hair',
    group: 'hair',
    styleKey: 'hair_style_name',
    colors: ['hair_color'],
  },
  {
    label: 'Gradient',
    group: 'hair',
    styleKey: 'grad_style_name',
    colors: ['grad_color'],
  },
  {
    label: 'Facial hair',
    group: 'hair',
    styleKey: 'facial_style_name',
    colors: ['facial_color'],
  },
  {
    label: 'Ears',
    group: 'ears',
    styleKey: 'ear_style',
    colors: ['ears_color1', 'ears_color2', 'ears_color3'],
    alpha: 'ears_alpha',
    clearable: true,
  },
  {
    label: 'Second ears',
    group: 'ears',
    styleKey: 'ear_secondary_style',
    colors: [],
    alpha: 'secondary_ears_alpha',
    clearable: true,
  },
  {
    label: 'Tail',
    group: 'tail',
    styleKey: 'tail_style',
    colors: ['tail_color1', 'tail_color2', 'tail_color3'],
    alpha: 'tail_alpha',
    clearable: true,
  },
  {
    label: 'Wings',
    group: 'wings',
    styleKey: 'wing_style',
    colors: ['wing_color1', 'wing_color2', 'wing_color3'],
    alpha: 'wing_alpha',
    clearable: true,
  },
];

/// Part, style, three swatch columns, options: fits the window without a horizontal scrollbar.
const TABLE_COLUMNS =
  '5.5em minmax(0, 1.3fr) repeat(3, 2.4em) minmax(10em, 1.2fr)';
const cellStyle = {
  minWidth: 0,
  alignSelf: 'center',
  minHeight: '1.9em',
  display: 'flex',
  alignItems: 'center',
} as const;
const swatchCell = { ...cellStyle, justifyContent: 'center' } as const;

/// A colour cell; blank when the style lacks the channel.
const ChannelCell = ({
  prefKey,
  values,
  shown,
}: {
  prefKey?: string;
  values: Record<string, unknown>;
  shown: boolean;
}) => (
  <Box style={swatchCell}>
    {shown && prefKey && (
      <ColorStrip
        compact
        colors={[{ key: prefKey, label: '' }]}
        values={values}
      />
    )}
  </Box>
);

/// A second-ear channel: its own colour, stored in the list ear_secondary_colors.
const SecondEarCell = ({
  index,
  color,
  fallback,
  shown,
}: {
  index: number;
  color?: string;
  /// What the channel draws while unset: the first ear's colour.
  fallback?: string;
  shown: boolean;
}) => {
  const { act } = useBackend();
  const send = (action: string, params: Record<string, unknown>) =>
    act('dq_editor_action', { editor: 'ear_secondary', action, params });
  return (
    <Box style={swatchCell}>
      {shown && (
        <ColorSwatch
          color={color ?? fallback ?? '#ffffff'}
          onPick={(hex) => send('set_color', { index, color: hex })}
        />
      )}
    </Box>
  );
};

const AlphaCell = ({
  alpha,
  values,
}: {
  alpha: string;
  values: Record<string, unknown>;
}) => (
  <ColorStrip
    compact
    colors={[]}
    alphas={[{ key: alpha, label: 'Opacity' }]}
    values={values}
  />
);

/// A part that can be absent offers None first among its styles (as hair offers bald), instead of a separate remove button.
export const withNoneChoice = (
  choices: PrefWidgetItem['choices'],
): Record<string, string> => ({
  '': 'None',
  ...Object.fromEntries(
    normalizeChoices(choices).filter(([v]) => !isNoStyle(v)),
  ),
});

/// Body thumbnails name the skin colour "skin": fill in the character's own.
export const withSkin = (
  thumbnails: Record<string, PrefThumbnail> | undefined,
  skin: unknown,
): Record<string, PrefThumbnail> => {
  const hex = normalizeHex(skin) ?? '#ffffff';
  const out: Record<string, PrefThumbnail> = {};
  for (const [key, thumb] of Object.entries(thumbnails ?? {})) {
    out[key] = thumb.layers
      ? {
          ...thumb,
          layers: thumb.layers.map((l) =>
            l.color === 'skin' ? { ...l, color: hex } : l,
          ),
        }
      : thumb;
  }
  return out;
};

/// A style cell: the picker, with None among the styles for a part that can be absent.
const StyleCell = ({
  item,
  clearable,
  skin,
}: {
  item: PrefWidgetItem | null;
  clearable?: boolean;
  skin: unknown;
}) => {
  if (!item) return <Box style={cellStyle} />;
  return (
    <Box style={cellStyle}>
      <BareField
        item={{
          ...item,
          choices: clearable ? withNoneChoice(item.choices) : item.choices,
          thumbnails: withSkin(item.thumbnails, skin),
        }}
      />
    </Box>
  );
};

/// One row per part: style, Primary, Secondary and Tertiary where the style has them, then its options.
const BodyTable = ({
  values,
  widgets,
  withValue,
  secondEarColors,
  secondEarFallback,
}: {
  values: Record<string, unknown>;
  widgets: Record<string, PrefWidgetItem>;
  withValue: (key: string) => PrefWidgetItem | null;
  secondEarColors: string[];
  secondEarFallback: string[];
}) => {
  const tailItem = withValue('tail_style');
  const tailValue = values.tail_style;
  const allTails = normalizeChoices(tailItem?.choices);
  const isTaur = (val: unknown) =>
    !!(tailItem?.thumbnails?.[String(val ?? '')] as StyleThumb | undefined)
      ?.taur;
  const taurNow = isTaur(tailValue);
  const header: Array<[string, boolean]> = [
    ['Part', false],
    ['Style', false],
    ['Pri', true],
    ['Sec', true],
    ['Ter', true],
    ['Options', false],
  ];
  return (
    <Section title="Body">
      <Box>
        <Box
          style={{
            display: 'grid',
            gridTemplateColumns: TABLE_COLUMNS,
            gap: '0.3em 0.4em',
            alignItems: 'center',
          }}
        >
          {header.map(([h, centred]) => (
            <Box
              key={h}
              bold
              color="label"
              style={{ textAlign: centred ? 'center' : undefined }}
            >
              {h}
            </Box>
          ))}
          {PART_ROWS.filter(
            (row) =>
              widgets[row.styleKey] &&
              (row.styleKey !== 'ear_secondary_style' ||
                !isNoStyle(values.ear_style) ||
                !isNoStyle(values.ear_secondary_style)),
          ).map((row) => {
            const isTail = row.styleKey === 'tail_style';
            const value = values[row.styleKey];
            const item = withValue(row.styleKey);
            const count = isNoStyle(value) ? 0 : channelsOf(item, value);
            if (isTail && taurNow) {
              return (
                <Box
                  key={row.label}
                  style={{ display: 'contents' }}
                  data-dq-anchor={groupAnchor('appearance', row.group)}
                >
                  <Box style={cellStyle}>{row.label}</Box>
                  <Box
                    color="label"
                    style={{ ...cellStyle, gridColumn: '2 / -1' }}
                  >
                    The taur body in Legs takes the place of a tail.
                  </Box>
                </Box>
              );
            }
            const shownItem =
              isTail && item
                ? {
                    ...item,
                    choices: allTails
                      .filter(([v]) => !isTaur(v))
                      .map(([v]) => v),
                  }
                : item;
            return (
              <Box
                key={row.label}
                style={{ display: 'contents' }}
                data-dq-anchor={groupAnchor('appearance', row.group)}
              >
                <Box style={cellStyle}>{row.label}</Box>
                <StyleCell
                  item={shownItem}
                  clearable={row.clearable}
                  skin={values.skin_color}
                />
                {[0, 1, 2].map((i) =>
                  row.styleKey === 'ear_secondary_style' ? (
                    <SecondEarCell
                      key={i}
                      index={i + 1}
                      color={secondEarColors[i]}
                      fallback={secondEarFallback[i]}
                      shown={i < count}
                    />
                  ) : (
                    <ChannelCell
                      key={i}
                      prefKey={row.colors[i]}
                      values={values}
                      shown={i < count && !!widgets[row.colors[i]]}
                    />
                  ),
                )}
                <Box style={cellStyle}>
                  {row.alpha && !isNoStyle(value) && widgets[row.alpha] && (
                    <AlphaCell alpha={row.alpha} values={values} />
                  )}
                </Box>
              </Box>
            );
          })}
          <LegsRow
            values={values}
            widgets={widgets}
            tailItem={tailItem}
            taurStyles={allTails.filter(([v]) => isTaur(v))}
            taurNow={taurNow}
          />
        </Box>
      </Box>
    </Section>
  );
};

/// The leg choices: Normal and Digitigrade, then every taur body (saved as the tail style it always was). The server sets the mode.
export const legChoices = (
  digitigrade: boolean,
  taurStyles: Array<[string, string]>,
): Record<string, string> => ({
  plantigrade: 'Normal',
  ...(digitigrade ? { digitigrade: 'Digitigrade' } : {}),
  ...Object.fromEntries(taurStyles),
});

/// Legs: one style picker. Normal, digitigrade or a taur body.
const LegsRow = ({
  values,
  widgets,
  tailItem,
  taurStyles,
  taurNow,
}: {
  values: Record<string, unknown>;
  widgets: Record<string, PrefWidgetItem>;
  tailItem: PrefWidgetItem | null;
  taurStyles: Array<[string, string]>;
  taurNow: boolean;
}) => {
  const { act } = useBackend();
  if (!widgets.digitigrade && !taurStyles.length) return null;
  const value = taurNow
    ? String(values.tail_style ?? '')
    : values.digitigrade
      ? 'digitigrade'
      : 'plantigrade';
  const count = taurNow ? channelsOf(tailItem, values.tail_style) : 0;
  const item: PrefWidgetItem = {
    ...(tailItem ?? widgets.digitigrade),
    key: 'legs',
    widget: 'thumbgrid',
    value,
    choices: legChoices(!!widgets.digitigrade, taurStyles),
    thumbnails: withSkin(tailItem?.thumbnails, values.skin_color),
  };
  return (
    <Box
      style={{ display: 'contents' }}
      data-dq-anchor={prefAnchor('digitigrade')}
    >
      <Box style={cellStyle}>Legs</Box>
      <Box style={cellStyle}>
        <Box style={{ flex: 1, minWidth: 0 }}>
          <PrefWidget
            item={item}
            onPick={(style) =>
              act('dq_editor_action', {
                editor: 'legs',
                action: 'set_leg_style',
                params: { style },
              })
            }
          />
        </Box>
      </Box>
      {['tail_color1', 'tail_color2', 'tail_color3'].map((key, i) => (
        <ChannelCell
          key={key}
          prefKey={key}
          values={values}
          shown={i < count && !!widgets[key]}
        />
      ))}
      <Box style={cellStyle}>
        {taurNow && widgets.tail_alpha && (
          <AlphaCell alpha="tail_alpha" values={values} />
        )}
      </Box>
    </Box>
  );
};

const BareField = ({ item }: { item: PrefWidgetItem }) => {
  const anchor = prefAnchor(item.key);
  const lit = useSearchHighlight(anchor);
  return (
    <Box
      data-dq-anchor={anchor}
      style={{ ...highlightStyle(lit), flex: 1, minWidth: 0 }}
    >
      <PrefWidget item={item} />
    </Box>
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
