// DQAdd — the Looks tab, laid out around the body. A body diagram on the left picks a region
// (head, ears, tail, wings, torso, arms, legs, hands & feet); the right shows just that region's
// styles, colours and markings, or everything ("Whole body"). Each part is one card: its style,
// one colour strip (primary/secondary/tertiary + opacity) and, for optional parts (ears, tail,
// wings), an "Add …" button while the part has no style.
//
// Every setting of the category stays reachable: anything a card does not claim is listed under
// "Other" in the whole-body view, and a settings-search jump to a field in another region
// switches to the whole-body view first.

import { type ReactNode, useContext, useEffect, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Box, Button, Section } from 'tgui-core/components';
import { WidgetGrid } from './CategoryPage';
import { ColorStrip, type StripColor } from './colors';
import { Switch } from './controls';
import { BodyMarkingsEditor } from './editors/BodyMarkingsEditor';
import { getEditor } from './editors';
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

export type Region =
  | 'all'
  | 'head'
  | 'ears'
  | 'tail'
  | 'wings'
  | 'torso'
  | 'arms'
  | 'legs'
  | 'extremities';

const REGION_LABELS: Record<Region, string> = {
  all: 'Whole body',
  head: 'Head & hair',
  ears: 'Ears',
  tail: 'Tail',
  wings: 'Wings',
  torso: 'Torso & skin',
  arms: 'Arms',
  legs: 'Legs',
  extremities: 'Hands & feet',
};

/// Organ tags (BP_*) a region's markings cover.
const REGION_ZONES: Partial<Record<Region, string[]>> = {
  head: ['head'],
  torso: ['torso', 'groin'],
  arms: ['l_arm', 'r_arm'],
  legs: ['l_leg', 'r_leg'],
  extremities: ['l_hand', 'r_hand', 'l_foot', 'r_foot'],
};

type CardId =
  | 'skin'
  | 'eyes'
  | 'hair'
  | 'ears'
  | 'tail'
  | 'wings'
  | 'legs'
  | 'blood'
  | 'markings'
  | 'organs'
  | 'palette'
  | 'chassis';

const REGION_CARDS: Record<Region, CardId[]> = {
  all: [
    'palette',
    'chassis',
    'skin',
    'eyes',
    'hair',
    'ears',
    'tail',
    'wings',
    'legs',
    'blood',
    'markings',
    'organs',
  ],
  head: ['hair', 'eyes', 'markings'],
  ears: ['ears'],
  tail: ['tail'],
  wings: ['wings'],
  torso: ['skin', 'blood', 'markings', 'organs'],
  arms: ['markings', 'organs'],
  legs: ['legs', 'markings', 'organs'],
  extremities: ['markings', 'organs'],
};

/// The prefs and editors each card owns (anything else lands in "Other").
const CARD_KEYS: Record<CardId, string[]> = {
  skin: [
    'skin_tone',
    'skin_color',
    'synth_color',
    'synth_color_rgb',
    'synth_markings',
  ],
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
  blood: ['b_type', 'blood_reagents', 'blood_color'],
  markings: ['body_markings'],
  organs: ['organs'],
  palette: ['color_palette'],
  chassis: ['robot_chassis'],
};

const KEY_TO_CARD: Record<string, CardId> = {};
for (const [card, keys] of Object.entries(CARD_KEYS)) {
  for (const key of keys) KEY_TO_CARD[key] = card as CardId;
}

/// The regions a card is shown in (for search jumps: stay in a region that shows the field).
const cardRegions = (card: CardId): Region[] =>
  (Object.keys(REGION_CARDS) as Region[]).filter((r) =>
    REGION_CARDS[r].includes(card),
  );

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
let rememberedRegion: Region = 'all';

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
  useEffect(() => {
    if (!highlight) return;
    const key = highlight.replace(/^(pref|editor):/, '');
    const card = KEY_TO_CARD[key];
    if (card) {
      if (!REGION_CARDS[region].includes(card)) {
        setRegion(cardRegions(card).includes(region) ? region : 'all');
      }
    } else if (region !== 'all' && highlight.startsWith('pref:')) {
      setRegion('all');
    } else if (highlight.startsWith('group:') && region !== 'all') {
      setRegion('all');
    }
  }, [highlight]);

  // Cards that have something to show in this play mode.
  const cardHasContent = (card: CardId) => CARD_KEYS[card].some(has);
  const claimed = new Set(
    Object.values(CARD_KEYS)
      .flat()
      .filter((k) => has(k)),
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

  const zones = REGION_ZONES[region];
  const cards = REGION_CARDS[region].filter(cardHasContent);

  const renderCard = (card: CardId) => {
    switch (card) {
      case 'skin':
        return (
          <PartCard key={card} title="Skin" anchorGroup={groupOf.skin_color}>
            <Fields keys={['skin_tone']} withValue={withValue} />
            <ColorStrip
              colors={pick(widgets, [['skin_color', 'Skin']])}
              values={values}
              matches={['Hair']}
            />
            <Fields
              keys={['synth_color', 'synth_markings']}
              withValue={withValue}
            />
            {!!values.synth_color && (
              <Box mt={0.3}>
                <ColorStrip
                  colors={pick(widgets, [['synth_color_rgb', 'Synth']])}
                  values={values}
                  matches={['Skin']}
                />
              </Box>
            )}
          </PartCard>
        );
      case 'eyes':
        return (
          <PartCard key={card} title="Eyes">
            <ColorStrip
              colors={pick(widgets, [['eyes_color', 'Eyes']])}
              values={values}
              matches={['Hair', 'Skin']}
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
                    ['hair_color', 'Hair'],
                    ['facial_color', 'Facial'],
                    // The gradient colour only matters with a gradient.
                    isNoStyle(values.grad_style_name)
                      ? null
                      : ['grad_color', 'Gradient'],
                  ].filter(Boolean) as Array<[string, string]>,
                )}
                values={values}
                matches={['Skin']}
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
                matches={['Skin', 'Hair']}
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
                matches={['Skin', 'Hair']}
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
      case 'blood':
        return (
          <PartCard key={card} title="Blood" anchorGroup="blood">
            <Fields keys={['b_type', 'blood_reagents']} withValue={withValue} />
            <Box mt={0.3}>
              <ColorStrip
                colors={pick(widgets, [['blood_color', 'Blood']])}
                values={values}
              />
            </Box>
          </PartCard>
        );
      case 'palette':
        return (
          <PartCard key={card} title="Palette" anchorGroup="palette">
            <Fields keys={['color_palette']} withValue={withValue} bare />
          </PartCard>
        );
      case 'markings':
        return (
          <Box key={card} data-dq-anchor={editorAnchor('body_markings')}>
            <BodyMarkingsEditor
              data={editorData.body_markings ?? {}}
              staticData={staticData?.body_markings}
              zones={zones}
              zoneLabel={zones ? REGION_LABELS[region] : undefined}
            />
          </Box>
        );
      case 'organs':
      case 'chassis': {
        const key = card === 'organs' ? 'organs' : 'robot_chassis';
        const Editor = getEditor(key);
        return (
          <Box key={card} data-dq-anchor={editorAnchor(key)}>
            <Section title={card === 'organs' ? 'Organs & limbs' : 'Chassis'}>
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
          flex: '0 0 12em',
          position: 'sticky',
          top: 0,
          display: 'flex',
          flexDirection: 'column',
          gap: '0.4em',
        }}
      >
        <BodyDiagram
          region={region}
          onPick={setRegion}
          values={values}
          available={{
            ears: has('ear_style'),
            tail: has('tail_style'),
            wings: has('wing_style'),
          }}
        />
        <Box style={{ display: 'flex', flexDirection: 'column', gap: '0.1em' }}>
          {(Object.keys(REGION_LABELS) as Region[])
            .filter((r) => REGION_CARDS[r].some(cardHasContent) || r === 'all')
            .filter(
              (r) => !REGION_ZONES[r] || REGION_CARDS[r].some(cardHasContent),
            )
            .map((r) => (
              <Button
                key={r}
                fluid
                selected={region === r}
                icon={r === 'all' ? 'person' : undefined}
                onClick={() => setRegion(r)}
              >
                {REGION_LABELS[r]}
              </Button>
            ))}
        </Box>
        {['preview_loadout', 'preview_job', 'animations_toggle'].some(has) && (
          <Section
            title="Preview"
            data-dq-anchor={groupAnchor('appearance', 'preview')}
          >
            <Box
              style={{ display: 'flex', flexDirection: 'column', gap: '0.3em' }}
            >
              {['preview_loadout', 'preview_job', 'animations_toggle']
                .map(withValue)
                .filter((item): item is PrefWidgetItem => !!item)
                .map((item) => (
                  <PreviewSwitch key={item.key} item={item} />
                ))}
            </Box>
          </Section>
        )}
      </Box>
      <Box
        style={{
          flex: '1 1 24em',
          minWidth: 0,
          display: 'grid',
          gridTemplateColumns:
            region === 'all'
              ? 'repeat(auto-fit, minmax(min(100%, max(22em, calc(50% - 0.25em))), 1fr))'
              : '1fr',
          gap: '0.5em',
          alignItems: 'start',
        }}
      >
        {cards.map((card) => {
          const node = renderCard(card);
          const wide =
            card === 'markings' ||
            card === 'organs' ||
            card === 'palette' ||
            card === 'chassis';
          return (
            <Box key={card} style={wide ? { gridColumn: '1 / -1' } : undefined}>
              {node}
            </Box>
          );
        })}
        {region === 'all' &&
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

/// Ears, tail and wings: while the part has no style the card is one "Add …" button that opens
/// the style picker; with a style it is the full card plus a Remove button.
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
  const [adding, setAdding] = useState(false);
  const empty = isNoStyle(values[styleKey]);
  const highlight = useContext(SearchHighlightContext);
  const lowerTitle = title.toLowerCase();
  // A search jump into this part opens it even while it has no style.
  const card = KEY_TO_CARD[styleKey];
  const searchHit =
    !!highlight &&
    !!card &&
    CARD_KEYS[card].some((key) => highlight === prefAnchor(key));
  // Once a search has opened the part it stays open (until the tab is left).
  const [revealed, setRevealed] = useState(false);
  useEffect(() => {
    if (searchHit) setRevealed(true);
  }, [searchHit]);
  const forced = searchHit || revealed;
  if (empty && !adding && !forced) {
    return (
      <PartCard title={title}>
        <Button
          icon="plus"
          onClick={() => setAdding(true)}
          tooltip={`This character has no ${lowerTitle}. Pick a style to add them.`}
        >
          Add {lowerTitle}
        </Button>
      </PartCard>
    );
  }
  if (empty && !forced) {
    const styleItem = withValue(styleKey);
    return (
      <PartCard
        title={`Add ${lowerTitle}`}
        buttons={
          <Button icon="xmark" onClick={() => setAdding(false)}>
            Cancel
          </Button>
        }
      >
        <Box color="label" mb={0.3}>
          Pick a style; colours appear once the part has one.
        </Box>
        {styleItem && (
          <BareField
            item={{ ...styleItem, props: { ...styleItem.props, open: true } }}
          />
        )}
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
            setAdding(false);
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

/// A front-view body schematic; each region is a clickable shape. Optional parts the character
/// lacks are drawn dashed. Colours follow the character's skin, hair and part colours.
const BodyDiagram = ({
  region,
  onPick,
  values,
  available,
}: {
  region: Region;
  onPick: (r: Region) => void;
  values: Record<string, unknown>;
  available: { ears: boolean; tail: boolean; wings: boolean };
}) => {
  const [hover, setHover] = useState<Region | null>(null);
  const col = (key: string, fallback: string) => {
    const v = String(values[key] ?? '');
    return /^#[0-9a-f]{6}$/i.test(v) ? v : fallback;
  };
  const skin = col('skin_color', '#c8a283');
  const hair = col('hair_color', '#5a3b1e');
  const part = (r: Region, fill: string, has = true) => ({
    fill: has ? fill : 'transparent',
    fillOpacity: has ? 0.85 : 0,
    stroke:
      region === r
        ? '#ffd75e'
        : hover === r
          ? '#fff'
          : 'rgba(255,255,255,0.45)',
    strokeWidth: region === r ? 2.2 : 1.1,
    strokeDasharray: has ? undefined : '3 2',
    cursor: 'pointer',
    onClick: () => onPick(region === r ? 'all' : r),
    onMouseEnter: () => setHover(r),
    onMouseLeave: () => setHover(null),
  });
  const hasEars = !isNoStyle(values.ear_style);
  const hasTail = !isNoStyle(values.tail_style);
  const hasWings = !isNoStyle(values.wing_style);
  return (
    <Box
      style={{
        background: 'rgba(0,0,0,0.25)',
        borderRadius: '0.3em',
        padding: '0.3em',
      }}
    >
      <svg
        viewBox="0 0 120 200"
        style={{ width: '100%', height: 'auto', display: 'block' }}
        role="img"
        aria-label="Body regions"
      >
        <title>Pick a body region</title>
        {available.wings && (
          <g {...part('wings', col('wing_color1', '#8a8a8a'), hasWings)}>
            <path d="M44 62 C20 40 6 50 4 86 C14 78 24 80 34 88 Z" />
            <path d="M76 62 C100 40 114 50 116 86 C106 78 96 80 86 88 Z" />
          </g>
        )}
        {available.tail && (
          <path
            {...part('tail', col('tail_color1', '#8a8a8a'), hasTail)}
            d="M66 112 C88 120 98 140 92 160 C90 150 84 138 70 126 Z"
          />
        )}
        {/* arms */}
        <g {...part('arms', skin)}>
          <path d="M40 58 L30 60 L22 104 L30 106 L38 74 Z" />
          <path d="M80 58 L90 60 L98 104 L90 106 L82 74 Z" />
        </g>
        {/* hands and feet */}
        <g {...part('extremities', skin)}>
          <ellipse cx="25" cy="112" rx="6" ry="7" />
          <ellipse cx="95" cy="112" rx="6" ry="7" />
          <path d="M44 184 L58 184 L58 192 L40 192 Z" />
          <path d="M62 184 L76 184 L80 192 L62 192 Z" />
        </g>
        {/* legs */}
        <g {...part('legs', skin)}>
          <path d="M44 118 L59 118 L58 184 L45 184 Z" />
          <path d="M61 118 L76 118 L75 184 L62 184 Z" />
        </g>
        {/* torso */}
        <path
          {...part('torso', skin)}
          d="M42 54 L78 54 L82 76 L78 120 L42 120 L38 76 Z"
        />
        {/* head */}
        <g {...part('head', skin)}>
          <rect x="54" y="44" width="12" height="10" />
          <ellipse cx="60" cy="30" rx="15" ry="17" />
          <path
            d="M45 28 C46 10 74 10 75 28 C70 20 50 20 45 28 Z"
            fill={hair}
            fillOpacity={0.95}
          />
        </g>
        {available.ears && (
          <g {...part('ears', col('ears_color1', '#8a8a8a'), hasEars)}>
            <path d="M46 18 L42 2 L54 13 Z" />
            <path d="M74 18 L78 2 L66 13 Z" />
          </g>
        )}
      </svg>
      <Box textAlign="center" color="label" fontSize="0.85em" mt={0.2}>
        {hover ? REGION_LABELS[hover] : REGION_LABELS[region]}
      </Box>
    </Box>
  );
};
