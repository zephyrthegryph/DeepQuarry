// The character setup's one colour model.
//
//  - The palette is five named slots (Primary ... Extra 2), each its own colour preference.
//  - ColorChoice: a colour field. Five slot dots plus a Custom swatch, the selected one highlighted. A dot links
//    the field (it saves the slot's name and follows the slot); Custom gives the field its own colour.
//  - ColorSwatch: a colour with no links (a slot itself, a pref that cannot link): a swatch opening a popover of
//    in-use and suggested colours and BYOND's picker.
//  - ColorStrip: a body part's colour fields and opacity.
//  - PaletteSlots: the slots themselves, each with its paint shortcut: while a slot is the brush, clicking a
//    field assigns it.
//
// The palette reaches every field through ColorToolsContext, which DQCharacterSetup fills from the cached values.

import { createContext, type ReactNode, useContext } from 'react';
import { useBackend } from 'tgui/backend';
import { Box, Button, Floating } from 'tgui-core/components';
import { SliderBox } from './controls';
import { highlightStyle, prefAnchor, useSearchHighlight } from './search';

export type SlotName =
  | 'primary'
  | 'secondary'
  | 'tertiary'
  | 'extra1'
  | 'extra2';

export const PALETTE_SLOTS: Array<{
  slot: SlotName;
  prefKey: string;
  label: string;
}> = [
  { slot: 'primary', prefKey: 'palette_primary', label: 'Primary (skin)' },
  { slot: 'secondary', prefKey: 'palette_secondary', label: 'Secondary' },
  { slot: 'tertiary', prefKey: 'palette_tertiary', label: 'Tertiary (eyes)' },
  { slot: 'extra1', prefKey: 'palette_extra1', label: 'Extra 1' },
  { slot: 'extra2', prefKey: 'palette_extra2', label: 'Extra 2' },
];

export const isSlotName = (value: unknown): value is SlotName =>
  PALETTE_SLOTS.some((s) => s.slot === value);

export type ColorTools = {
  /// Each slot's current colour.
  slots: Record<SlotName, string>;
  /// Pref key -> the slot it links to ("" or absent: its own colour).
  links: Record<string, string>;
  /// Every colour the character already wears, distinct, in the order they appear.
  inUse: string[];
  /// The slot being painted with, if any.
  brush: SlotName | null;
  setBrush: (slot: SlotName | null) => void;
};

/// The slots' colours from the preference values.
export const slotColors = (
  values: Record<string, unknown>,
): Record<SlotName, string> => {
  const out = {} as Record<SlotName, string>;
  for (const { slot, prefKey } of PALETTE_SLOTS) {
    out[slot] = normalizeHex(values[prefKey]) ?? '#000000';
  }
  return out;
};

export const ColorToolsContext = createContext<ColorTools>({
  slots: {} as Record<SlotName, string>,
  links: {},
  inUse: [],
  brush: null,
  setBrush: () => {},
});

export const useColorTools = () => useContext(ColorToolsContext);

const HEX = /^#[0-9a-f]{6}$/i;
export const normalizeHex = (value: unknown): string | null => {
  const s = String(value ?? '').trim();
  const withHash = s.startsWith('#') ? s : `#${s}`;
  if (HEX.test(withHash)) return withHash.toLowerCase();
  if (/^#[0-9a-f]{3}$/i.test(withHash)) {
    const [, r, g, b] = withHash;
    return `#${r}${r}${g}${g}${b}${b}`.toLowerCase();
  }
  return null;
};

/// The colours the character already uses: every "#rrggbb" among the preference values (a colour pref, or a
/// list of them), distinct, at most `limit`.
export const colorsInUse = (
  values: Record<string, unknown>,
  limit = 16,
): string[] => {
  const seen = new Set<string>();
  for (const value of Object.values(values)) {
    for (const item of Array.isArray(value) ? value : [value]) {
      const hex =
        typeof item === 'string' && HEX.test(item) ? normalizeHex(item) : null;
      if (hex) seen.add(hex);
      if (seen.size >= limit) return [...seen];
    }
  }
  return [...seen];
};

export type ColorCategory = 'skin' | 'hair' | 'eyes' | 'other';

/// Which curated set suits a colour, from the pref key or the label that names it.
export const colorCategory = (name: string | undefined): ColorCategory => {
  const n = (name ?? '').toLowerCase();
  if (/hair|facial|beard|gradient|grad_/.test(n)) return 'hair';
  if (/eye/.test(n)) return 'eyes';
  if (/skin|body|fur|scale/.test(n)) return 'skin';
  return 'other';
};

/// A short curated set per category, offered as quick swatches beside the Custom picker.
export const SUGGESTED_COLORS: Record<ColorCategory, string[]> = {
  skin: [
    '#f5d7c3',
    '#e8b796',
    '#c8a283',
    '#a97c5b',
    '#7c5438',
    '#523221',
    '#d9e4ec',
    '#9fc7a0',
  ],
  hair: [
    '#0f0f10',
    '#3b2a1c',
    '#5a3b1e',
    '#8b5a2b',
    '#c28a45',
    '#e6c88a',
    '#b3342d',
    '#c8c8cc',
  ],
  eyes: [
    '#3b2a1c',
    '#6b4a2b',
    '#2e6f9e',
    '#3f8f5a',
    '#7a8f3f',
    '#8a8a92',
    '#a2306b',
    '#d4a017',
  ],
  other: [
    '#ffffff',
    '#c8c8cc',
    '#6b6b73',
    '#1c1c20',
    '#b3342d',
    '#d98a2b',
    '#3f8f5a',
    '#2e6f9e',
  ],
};

export const suggestedColors = (name: string | undefined): string[] =>
  SUGGESTED_COLORS[colorCategory(name)];

const swatchStyle = (color: string, size = 1.25) => ({
  display: 'inline-block',
  width: `${size}em`,
  height: `${size}em`,
  borderRadius: '0.2em',
  background: color,
  border: '0.0833em solid rgba(255,255,255,0.45)',
  boxShadow: 'inset 0 0 0 0.0833em rgba(0,0,0,0.35)',
  verticalAlign: 'middle',
  flex: '0 0 auto',
});

const QuickSwatches = ({
  title,
  colors,
  current,
  onPick,
}: {
  title: string;
  colors: string[];
  current: string;
  onPick: (hex: string) => void;
}) =>
  colors.length === 0 ? null : (
    <>
      <Box color="label" fontSize="0.85em" mb={0.2}>
        {title}
      </Box>
      <Box
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '0.25em',
          marginBottom: '0.4em',
        }}
      >
        {colors.map((c) => (
          <span
            key={c}
            title={c}
            onClick={() => onPick(c)}
            style={{
              ...swatchStyle(c, 1.25),
              cursor: 'pointer',
              outline: c === current ? '0.12em solid #fff' : undefined,
            }}
          />
        ))}
      </Box>
    </>
  );

/// One colour: a swatch that opens the picker popover. `onPick` writes a colour directly;
/// `onCustom` opens BYOND's own colour picker.
export const ColorSwatch = ({
  color,
  label,
  onPick,
  onCustom,
  showHex,
  extra,
  category,
}: {
  color: string;
  label?: string;
  /// Name used to pick the curated set (a pref key); defaults to the label.
  category?: string;
  onPick: (hex: string) => void;
  onCustom: () => void;
  showHex?: boolean;
  /// Extra rows for the popover (e.g. a pref's "unset" action).
  extra?: ReactNode;
}) => {
  const { inUse } = useColorTools();
  const suggested = suggestedColors(category ?? label);
  const hex = normalizeHex(color) ?? '#000000';
  return (
    <Floating
      placement="bottom-start"
      closeAfterInteract
      contentStyles={{
        zIndex: 60,
        background: 'var(--color-base, #252525)',
        border: '0.0833em solid rgba(255,255,255,0.2)',
        borderRadius: '0.25em',
        boxShadow: '0 0.3em 1em rgba(0,0,0,0.6)',
        padding: '0.4em',
        width: '13em',
      }}
      content={
        <Box>
          {label && (
            <Box bold mb={0.3}>
              {label}
            </Box>
          )}
          <QuickSwatches
            title="In use"
            colors={inUse}
            current={hex}
            onPick={onPick}
          />
          <QuickSwatches
            title="Suggested"
            colors={suggested}
            current={hex}
            onPick={onPick}
          />
          <Button fluid icon="eye-dropper" onClick={onCustom}>
            Custom…
          </Button>
          {extra}
        </Box>
      }
    >
      <span
        className="dq-swatch"
        title={label ? `${label}: ${hex}` : hex}
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: '0.35em',
          cursor: 'pointer',
          padding: '0.1em 0.3em 0.1em 0.1em',
          borderRadius: '0.25em',
          background: 'rgba(255,255,255,0.06)',
        }}
      >
        <span style={swatchStyle(hex)} />
        {showHex && <span style={{ fontFamily: 'monospace' }}>{hex}</span>}
        {label && !showHex && (
          <span style={{ color: 'rgba(255,255,255,0.9)' }}>{label}</span>
        )}
      </span>
    </Floating>
  );
};

/// A colour preference's swatch: writes through dq_update_preference / dq_pick_color.
export const PrefColorSwatch = ({
  prefKey,
  value,
  label,
  showHex,
  extra,
}: {
  prefKey: string;
  value: unknown;
  label?: string;
  showHex?: boolean;
  extra?: ReactNode;
}) => {
  const { act } = useBackend();
  return (
    <ColorSwatch
      color={String(value ?? '#000000')}
      label={label}
      showHex={showHex}
      extra={extra}
      category={prefKey}
      onPick={(hex) =>
        act('dq_update_preference', { key: prefKey, value: hex })
      }
      onCustom={() => act('dq_pick_color', { key: prefKey })}
    />
  );
};

export type StripColor = { key: string; label: string };

/// A colour field: the five slot dots plus Custom. `link` is the slot it follows, if any. `onLink` links it,
/// `onPick` gives it a colour of its own, `onCustom` opens BYOND's picker. While a slot is the brush, a click
/// anywhere on the field assigns that slot.
export const ColorChoice = ({
  color,
  link,
  label,
  category,
  onLink,
  onPick,
  onCustom,
  compact,
}: {
  color: string;
  link?: string;
  label?: string;
  category?: string;
  onLink: (slot: SlotName) => void;
  onPick: (hex: string) => void;
  onCustom: () => void;
  /// One swatch; the slots move into its popover (a table cell).
  compact?: boolean;
}) => {
  const { slots, brush } = useColorTools();
  const linked = isSlotName(link) ? link : null;
  const hex = normalizeHex(color) ?? '#000000';
  if (compact) {
    return (
      <span
        className="dq-color-choice"
        data-link={linked ?? 'custom'}
        title={linked ? `Linked to ${linked}` : hex}
        onClickCapture={(e) => {
          if (!brush) return;
          e.stopPropagation();
          e.preventDefault();
          onLink(brush);
        }}
        style={{
          display: 'inline-flex',
          borderRadius: '0.25em',
          outline: linked ? '0.12em dashed rgba(255,255,255,0.7)' : undefined,
          outlineOffset: '0.08em',
          cursor: brush ? 'copy' : undefined,
        }}
      >
        <ColorSwatch
          color={hex}
          category={category ?? label}
          onPick={onPick}
          onCustom={onCustom}
          extra={
            <Box mt={0.3}>
              <Box color="label" fontSize="0.85em" mb={0.2}>
                Link to a palette slot
              </Box>
              <Box style={{ display: 'flex', gap: '0.3em' }}>
                {PALETTE_SLOTS.map(({ slot, label: slotLabel }) => (
                  <span
                    key={slot}
                    className="dq-slot-dot"
                    title={`Link to ${slotLabel}`}
                    onClick={() => onLink(slot)}
                    style={{
                      ...swatchStyle(slots[slot] ?? '#000000', 1.25),
                      borderRadius: '50%',
                      cursor: 'pointer',
                      outline:
                        linked === slot ? '0.15em solid #fff' : undefined,
                      outlineOffset: '0.08em',
                    }}
                  />
                ))}
              </Box>
            </Box>
          }
        />
      </span>
    );
  }
  return (
    <span
      className="dq-color-choice"
      data-link={linked ?? 'custom'}
      onClickCapture={(e) => {
        if (!brush) return;
        e.stopPropagation();
        e.preventDefault();
        onLink(brush);
      }}
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        flexWrap: 'wrap',
        gap: '0.3em',
        padding: '0.15em 0.3em',
        borderRadius: '0.25em',
        background: 'rgba(255,255,255,0.05)',
        cursor: brush ? 'copy' : undefined,
      }}
    >
      {label && <span style={{ minWidth: '4.5em' }}>{label}</span>}
      {PALETTE_SLOTS.map(({ slot, label: slotLabel }) => (
        <span
          key={slot}
          className="dq-slot-dot"
          title={`Link to ${slotLabel}`}
          onClick={() => onLink(slot)}
          style={{
            ...swatchStyle(slots[slot] ?? '#000000', 1.25),
            borderRadius: '50%',
            cursor: 'pointer',
            outline: linked === slot ? '0.15em solid #fff' : undefined,
            outlineOffset: '0.08em',
          }}
        />
      ))}
      <span
        style={{
          borderRadius: '0.25em',
          outline: linked ? undefined : '0.15em solid #fff',
          outlineOffset: '0.08em',
          display: 'inline-flex',
        }}
      >
        <ColorSwatch
          color={hex}
          label="Custom"
          category={category ?? label}
          onPick={onPick}
          onCustom={onCustom}
        />
      </span>
    </span>
  );
};

/// A body part's colour fields and opacity.
export const ColorStrip = ({
  colors,
  alphas,
  values,
  compact,
}: {
  colors: StripColor[];
  /// Swatches only, and opacity sliders that shrink: for table cells.
  compact?: boolean;
  /// Opacity prefs (0-255) shown after the fields.
  alphas?: StripColor[];
  values: Record<string, unknown>;
}) => {
  const { act } = useBackend();
  const { links } = useColorTools();
  return (
    <Box
      style={{
        display: 'flex',
        flexWrap: 'wrap',
        alignItems: 'center',
        gap: '0.35em 0.6em',
      }}
    >
      {colors.map((c) => (
        <SwatchAnchor key={c.key} prefKey={c.key}>
          <ColorChoice
            color={String(values[c.key] ?? '#000000')}
            link={links[c.key]}
            label={c.label}
            category={c.key}
            compact={compact}
            onLink={(slot) =>
              act('dq_update_preference', { key: c.key, value: slot })
            }
            onPick={(hex) =>
              act('dq_update_preference', { key: c.key, value: hex })
            }
            onCustom={() => act('dq_pick_color', { key: c.key })}
          />
        </SwatchAnchor>
      ))}
      {(alphas ?? []).map((a) => (
        <SwatchAnchor key={a.key} prefKey={a.key} grow>
          <Box
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.4em',
              minWidth: compact ? 0 : '12em',
              flex: compact ? '1 1 0' : '1 1 12em',
            }}
          >
            <Box color="label" fontSize="0.85em" style={{ flex: '0 0 auto' }}>
              {a.label}
            </Box>
            <Box style={{ flex: 1, minWidth: 0 }}>
              <SliderBox
                serverValue={Number(values[a.key] ?? 255)}
                min={0}
                max={255}
                step={1}
                onCommit={(v) =>
                  act('dq_update_preference', { key: a.key, value: v })
                }
              />
            </Box>
          </Box>
        </SwatchAnchor>
      ))}
    </Box>
  );
};

/// Wraps a control so the settings search can find and highlight it.
const SwatchAnchor = ({
  prefKey,
  children,
  grow,
}: {
  prefKey: string;
  children: ReactNode;
  grow?: boolean;
}) => {
  const anchor = prefAnchor(prefKey);
  const lit = useSearchHighlight(anchor);
  return (
    <Box
      data-dq-anchor={anchor}
      style={{
        display: grow ? 'flex' : 'inline-flex',
        flex: grow ? '1 1 12em' : undefined,
        ...highlightStyle(lit),
      }}
    >
      {children}
    </Box>
  );
};

/// The palette: each slot's colour and name. Clicking the name makes it the brush.
export const PaletteSlots = ({
  values,
}: {
  values: Record<string, unknown>;
}) => {
  const { brush, setBrush } = useColorTools();
  return (
    <Box style={{ display: 'flex', flexDirection: 'column', gap: '0.2em' }}>
      {PALETTE_SLOTS.map(({ slot, prefKey, label }) => (
        <SwatchAnchor key={slot} prefKey={prefKey}>
          <Box style={{ display: 'flex', alignItems: 'center', gap: '0.3em' }}>
            <PrefColorSwatch prefKey={prefKey} value={values[prefKey]} />
            <Button
              fluid
              color="transparent"
              selected={brush === slot}
              tooltip={
                brush === slot
                  ? 'Stop painting'
                  : `Paint: click colour fields to link them to ${label}`
              }
              onClick={() => setBrush(brush === slot ? null : slot)}
            >
              {label}
            </Button>
          </Box>
        </SwatchAnchor>
      ))}
    </Box>
  );
};
