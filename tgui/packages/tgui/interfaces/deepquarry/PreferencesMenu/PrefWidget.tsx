// DQAdd — Auto-renders a single /datum/preference widget. The DM side picks the widget
// type via /datum/preference.get_widget(); this component dispatches to the right control.

import { useCallback, useEffect, useRef, useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Dropdown,
  Input,
  Stack,
  TextArea,
} from 'tgui-core/components';
import { PrefColorSwatch } from './colors';
import { SearchableDropdown, Segmented, SliderBox, Switch } from './controls';
import {
  ColorizedImage,
  CustomImageButton,
  HairGradientImage,
  type ImageLayer,
  LayeredImage,
} from './helper_components';
import type { PrefThumbnail, PrefWidgetItem } from './types';

type Props = {
  item: PrefWidgetItem;
  /// Where a pick goes instead of the pref named by item.key (a picker an editor owns, e.g. Legs).
  onPick?: (value: string) => void;
};

const sendUpdate = (
  act: ReturnType<typeof useBackend>['act'],
  key: string,
  value: unknown,
) => {
  act('dq_update_preference', { key, value });
};

/// Local-buffered Input that only fires onCommit on blur or Enter, so the ~1Hz tgui
/// poll can't yank the caret position mid-typing. Re-syncs the buffer on external
/// value changes (server poll reflecting another tab's write).
const BufferedTextInput = ({
  value,
  onCommit,
}: {
  value: string;
  onCommit: (next: string) => void;
}) => {
  const [draft, setDraft] = useState(value);
  useEffect(() => setDraft(value), [value]);
  return (
    <Input
      fluid
      value={draft}
      onChange={(v) => setDraft(v)}
      onBlur={() => {
        if (draft !== value) onCommit(draft);
      }}
      onEnter={() => {
        if (draft !== value) onCommit(draft);
      }}
    />
  );
};

const BufferedTextArea = ({
  value,
  onCommit,
}: {
  value: string;
  onCommit: (next: string) => void;
}) => {
  const [draft, setDraft] = useState(value);
  useEffect(() => setDraft(value), [value]);
  return (
    <TextArea
      fluid
      height="5em"
      value={draft}
      onChange={(v) => setDraft(v)}
      onBlur={() => {
        if (draft !== value) onCommit(draft);
      }}
    />
  );
};

/// Choice lists at or under this many entries (with short labels) render as a segmented row.
const SEGMENTED_MAX = 4;
const SEGMENTED_MAX_LABEL_CHARS = 36;
/// Choice lists over this many entries get a filter box.
const SEARCHABLE_MIN = 9;

export type ResolvedWidget =
  | 'text'
  | 'longtext'
  | 'number'
  | 'switch'
  | 'color'
  | 'segmented'
  | 'dropdown'
  | 'search_dropdown'
  | 'multi'
  | 'thumbgrid'
  | 'palette'
  | 'none';

/// The one place that decides which control a pref gets. The server's hint (get_widget) says
/// what kind of value it is; the control for that kind is chosen here, the same way on every
/// tab: toggles are switches, short choice lists segmented buttons, long ones a searchable
/// dropdown, numbers a slider plus a box.
export const resolveWidget = (item: PrefWidgetItem): ResolvedWidget => {
  switch (item.widget) {
    case 'boolean':
      return 'switch';
    case 'number':
    case 'slider':
      return 'number';
    case 'radio':
    case 'dropdown': {
      // Options that explain themselves need the list whose rows take a tooltip.
      if (item.props?.option_tooltips) return 'search_dropdown';
      const choices = normalizeChoices(item.choices);
      const chars = choices.reduce((n, [, label]) => n + label.length, 0);
      if (
        choices.length > 0 &&
        choices.length <= SEGMENTED_MAX &&
        chars <= SEGMENTED_MAX_LABEL_CHARS
      ) {
        return 'segmented';
      }
      return choices.length >= SEARCHABLE_MIN ? 'search_dropdown' : 'dropdown';
    }
    case 'text':
    case 'longtext':
    case 'color':
    case 'multi':
    case 'thumbgrid':
    case 'palette':
      return item.widget;
    case 'hidden':
    case 'editor':
      return 'none';
    default:
      return 'text';
  }
};

export const PrefWidget = ({ item, onPick }: Props) => {
  const { act } = useBackend();

  switch (resolveWidget(item)) {
    case 'text':
      // Buffered: flushes on blur/Enter so the ~1 Hz poll can't yank the caret mid-typing.
      return (
        <BufferedTextInput
          value={String(item.value ?? '')}
          onCommit={(v) => sendUpdate(act, item.key, v)}
        />
      );

    case 'longtext':
      return (
        <BufferedTextArea
          value={String(item.value ?? '')}
          onCommit={(v) => sendUpdate(act, item.key, v)}
        />
      );

    case 'number': {
      const min = Number((item.props.min as number | undefined) ?? 0);
      const max = Number((item.props.max as number | undefined) ?? 100);
      const step = Number((item.props.step as number | undefined) ?? 1);
      return (
        <SliderBox
          serverValue={Number(item.value ?? min)}
          min={min}
          max={max}
          step={step}
          onCommit={(v) => sendUpdate(act, item.key, v)}
        />
      );
    }

    case 'switch':
      return (
        <Switch
          checked={!!item.value}
          onToggle={() => sendUpdate(act, item.key, !item.value)}
        />
      );

    case 'color': {
      // A pref may declare a sentinel value meaning "no colour chosen" (runechat_color's
      // black means "colour from the name"); show its label, not a black swatch.
      const hex = String(item.value ?? '#000000');
      const unsetValue = item.props?.unset_value as string | undefined;
      const unsetLabel = String(item.props?.unset_label ?? 'Unset');
      const isUnset =
        unsetValue !== undefined &&
        hex.toLowerCase() === String(unsetValue).toLowerCase();
      const unsetButton =
        unsetValue !== undefined && !isUnset ? (
          <Button
            fluid
            icon="undo"
            onClick={() => sendUpdate(act, item.key, unsetValue)}
          >
            {unsetLabel}
          </Button>
        ) : undefined;
      return (
        <Stack align="center">
          <Stack.Item>
            {isUnset ? (
              <Button onClick={() => act('dq_pick_color', { key: item.key })}>
                {unsetLabel}
              </Button>
            ) : (
              <PrefColorSwatch
                prefKey={item.key}
                value={hex}
                showHex
                extra={unsetButton}
              />
            )}
          </Stack.Item>
        </Stack>
      );
    }

    case 'segmented':
      return (
        <Segmented
          options={normalizeChoices(item.choices)}
          value={String(item.value ?? '')}
          onSelect={(val) => sendUpdate(act, item.key, val)}
        />
      );

    case 'search_dropdown':
      return (
        <SearchableDropdown
          options={normalizeChoices(item.choices)}
          value={String(item.value ?? '')}
          onSelect={(val) => sendUpdate(act, item.key, val)}
          tooltips={
            item.props?.option_tooltips as Record<string, string> | undefined
          }
        />
      );

    case 'dropdown': {
      const choices = normalizeChoices(item.choices);
      const options = choices.map(([val, label]) => ({
        value: val,
        displayText: label,
      }));
      const currentVal = String(item.value ?? '');
      // tgui-core Dropdown doesn't look up the option label from the value on its own.
      const currentLabel =
        options.find((o) => o.value === currentVal)?.displayText ?? currentVal;
      return (
        <Dropdown
          fluid
          selected={currentVal}
          displayText={currentLabel}
          options={options}
          onSelected={(val) => sendUpdate(act, item.key, val)}
        />
      );
    }

    case 'multi': {
      const selected = Array.isArray(item.value)
        ? (item.value as string[])
        : [];
      const choices = normalizeChoices(item.choices);
      return (
        <Stack wrap>
          {choices.map(([val, label]) => (
            <Stack.Item key={val}>
              <Button
                selected={selected.includes(val)}
                onClick={() => {
                  const next = selected.includes(val)
                    ? selected.filter((s) => s !== val)
                    : [...selected, val];
                  sendUpdate(act, item.key, next);
                }}
              >
                {label}
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      );
    }

    case 'thumbgrid':
      return (
        <ThumbgridPicker
          item={item}
          onPick={(val) =>
            onPick ? onPick(val) : sendUpdate(act, item.key, val)
          }
        />
      );

    case 'none':
      return null;

    default:
      // 'auto' (the expected fallthrough) plus any unknown widget kind. 'auto' should have
      // been resolved by /datum/preference.get_widget() on the DM side; if we land here,
      // something registered a pref without picking a widget — render a text input rather
      // than a read-only display so it's at least editable.
      return (
        <Input
          fluid
          value={String(item.value ?? '')}
          onChange={(v) => sendUpdate(act, item.key, v)}
        />
      );
  }
};

/// A flat choice list carries raw values; an all-lowercase identifier ("male",
/// "fadeup_low", "default") is shown capitalized with spaces, anything already
/// written for people ("Arrivals Shuttle", "A+") is shown as is.
function humanizeChoice(value: string): string {
  // A sprite accessory path ("/datum/sprite_accessory/tail/special/orca_tail") reads as its last part.
  if (value.startsWith('/datum/')) {
    value = value.slice(value.lastIndexOf('/') + 1);
  }
  if (!/^[a-z][a-z0-9_]*$/.test(value)) return value;
  const spaced = value.replace(/_/g, ' ');
  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

export function normalizeChoices(
  choices: PrefWidgetItem['choices'],
): Array<[string, string]> {
  if (!choices) return [];
  if (Array.isArray(choices)) {
    return choices.map((v) => [v, humanizeChoice(v)]);
  }
  return Object.entries(choices);
}

/// Inline thumbnail picker. The Change button opens a panel that expands inline below the trigger row, scoped to
/// the widget's grid cell (no full-window Dimmer overlay), with its own scroll for long lists (hair and marking
/// catalogs run into the hundreds). Picking a style keeps it open so styles can be compared; it closes on its Close
/// button, Escape or a click outside it.
const THUMB_BACKING = '#9a9a9a';

const isNoneValue = (value: string) => {
  const s = value.trim().toLowerCase();
  return s === '' || s === 'none' || s === 'null';
};

/// The choice a value selects: itself, or None ('') for a blank or "none" value when the choices offer None.
export const selectedChoice = (
  choices: Array<[string, string]>,
  value: unknown,
): string => {
  const current = String(value ?? '');
  if (choices.some(([v]) => v === current)) return current;
  if (isNoneValue(current) && choices.some(([v]) => v === '')) return '';
  return current;
};

/// The sprites a choice draws: its own layers (the body, for None and the leg modes), or its sprite on the picker's
/// base (the body, when None marks itself the base) or alone. Null when it has no sprite.
export const thumbLayers = (
  thumbs: Record<string, PrefThumbnail>,
  value: string,
): ImageLayer[] | null => {
  const t = thumbs[value];
  if (!t) return null;
  if (t.layers?.length) return t.layers;
  if (!t.icon || !t.icon_state) return null;
  const base = thumbs['']?.base ? (thumbs[''].layers ?? []) : [];
  return [
    ...base,
    { icon: t.icon, icon_state: t.icon_state, color: '#ffffff' },
  ];
};

/// A choice's picture: a hair gradient on its hair, or its layers.
const ThumbImage = ({
  thumbs,
  value,
  size,
}: {
  thumbs: Record<string, PrefThumbnail>;
  value: string;
  size?: number;
}) => {
  const t = thumbs[value];
  if (t?.hair_icon && t.hair_state && t.icon && t.icon_state) {
    return (
      <HairGradientImage
        hairRef={t.hair_icon}
        hairState={t.hair_state}
        gradientRef={t.icon}
        gradientState={t.icon_state}
        size={size}
      />
    );
  }
  const layers = thumbLayers(thumbs, value);
  if (!layers) return null;
  if (layers.length === 1 && layers[0].color === '#ffffff') {
    return (
      <ColorizedImage
        iconRef={layers[0].icon}
        iconState={layers[0].icon_state}
        color="#ffffff"
        size={size}
      />
    );
  }
  return <LayeredImage layers={layers} size={size} />;
};

/// Closes an open panel on Escape or on a press outside `ref`.
const useDismiss = (
  open: boolean,
  ref: { current: HTMLElement | null },
  close: () => void,
) => {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
    };
    const onDown = (e: MouseEvent) => {
      const target = e.target as Node | null;
      if (ref.current && target && !ref.current.contains(target)) close();
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('mousedown', onDown);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('mousedown', onDown);
    };
  }, [open, ref, close]);
};

export const ThumbgridPicker = ({
  item,
  onPick,
}: {
  item: PrefWidgetItem;
  onPick: (val: string) => void;
}) => {
  const choices = normalizeChoices(item.choices);
  const thumbs = item.thumbnails ?? {};
  // props.open: the caller wants the picker shown at once (an "Add tail" button).
  const [open, setOpen] = useState(!!item.props?.open);
  const [search, setSearch] = useState('');
  const rootRef = useRef<HTMLDivElement | null>(null);
  const close = useCallback(() => setOpen(false), []);
  useDismiss(open, rootRef, close);
  const currentVal = selectedChoice(choices, item.value);
  // Display the user-facing label for the current selection, not the raw value
  // (which is the asset key — e.g. "marking_arrow_chest" instead of "Chest Arrow").
  const currentLabel =
    choices.find(([val]) => val === currentVal)?.[1] ?? currentVal;
  const hasCurrentThumb =
    !!thumbLayers(thumbs, currentVal) || !!thumbs[currentVal]?.hair_icon;

  const lcSearch = search.trim().toLowerCase();
  const filtered = choices.filter(
    ([val, label]) =>
      !lcSearch ||
      val.toLowerCase().includes(lcSearch) ||
      label.toLowerCase().includes(lcSearch),
  );

  return (
    <div ref={rootRef} style={{ width: '100%' }}>
      <Stack align="center">
        {hasCurrentThumb ? (
          <Stack.Item>
            {/* Hair and beard art is near-black (the colour is added in game): it needs a light backing. */}
            <Box
              style={{
                display: 'flex',
                background: THUMB_BACKING,
                borderRadius: '0.2em',
              }}
            >
              <ThumbImage thumbs={thumbs} value={currentVal} size={32} />
            </Box>
          </Stack.Item>
        ) : null}
        <Stack.Item grow style={{ minWidth: 0 }}>
          <Box
            style={{
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}
          >
            {currentLabel || '—'}
          </Box>
        </Stack.Item>
        <Stack.Item style={{ marginLeft: 'auto' }}>
          <Button
            icon={open ? 'xmark' : 'grip'}
            color={open ? 'bad' : undefined}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? 'Close' : 'Change'}
          </Button>
        </Stack.Item>
      </Stack>
      {open && (
        <Box
          mt={0.5}
          p={0.5}
          style={{
            borderRadius: '0.3em',
            border: '0.0833em solid rgba(255,255,255,0.1)',
            background: 'rgba(0,0,0,0.2)',
          }}
        >
          <Box mb={0.5}>
            <Input
              fluid
              expensive
              placeholder="Search…"
              value={search}
              onChange={(v) => setSearch(v)}
            />
          </Box>
          <Box style={{ maxHeight: '18em', overflowY: 'auto' }}>
            <Stack wrap>
              {filtered.map(([val, label]) => {
                const pictured =
                  !!thumbLayers(thumbs, val) || !!thumbs[val]?.hair_icon;
                return (
                  <Stack.Item key={val} m={0.25}>
                    {pictured ? (
                      <CustomImageButton
                        image={<ThumbImage thumbs={thumbs} value={val} />}
                        tooltip={label}
                        selected={val === currentVal}
                        onClick={() => onPick(val)}
                      >
                        {label}
                      </CustomImageButton>
                    ) : (
                      <Button
                        selected={val === currentVal}
                        onClick={() => onPick(val)}
                      >
                        {label}
                      </Button>
                    )}
                  </Stack.Item>
                );
              })}
            </Stack>
          </Box>
        </Box>
      )}
    </div>
  );
};
