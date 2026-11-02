// The character setup's one colour model.
//
//  - The palette is five named slots (Primary ... Extra 2), each its own colour preference.
//  - ColorChoice: a colour field. Five slot dots plus a Custom swatch, the selected one highlighted. A dot links
//    the field (it saves the slot's name and follows the slot); Custom gives the field its own colour.
//  - ColorSwatch: a swatch opening a popover of the palette's colours and Custom, a colour picker in place.
//  - ColorStrip: a body part's colour fields and opacity.
//  - PaletteSlots: the slots themselves, each with its paint shortcut: while a slot is the brush, clicking a
//    field assigns it.
//
// The palette reaches every field through ColorToolsContext, which DQCharacterSetup fills from the cached values.

import { createContext, type ReactNode, useContext, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { type HsvaColor, hexToHsva, hsvaToHex } from 'tgui-core/color';
import { Box, Button, Floating, Input } from 'tgui-core/components';
import { Hue, SaturationValue } from '../../ColorPickerModal';
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

/// The custom colour, picked in place: saturation and value, hue, and the hex. Apply writes it.
export const InlineColorPicker = ({
  initial,
  onApply,
}: {
  initial: string;
  onApply: (hex: string) => void;
}) => {
  const [hsva, setHsva] = useState<HsvaColor>(() => hexToHsva(initial));
  const [hexText, setHexText] = useState(initial);
  const hex = hsvaToHex(hsva).slice(0, 7).toLowerCase();
  const change = (params: Partial<HsvaColor>) => {
    setHsva((current) => {
      const next = { ...current, ...params };
      setHexText(hsvaToHex(next).slice(0, 7).toLowerCase());
      return next;
    });
  };
  return (
    <Box className="dq-inline-color-picker" mt={0.3}>
      <div className="react-colorful" style={{ width: '100%', height: '9em' }}>
        <SaturationValue hsva={hsva} onChange={change} />
        <Hue
          hue={hsva.h}
          onChange={change}
          className="react-colorful__last-control"
        />
      </div>
      <Box
        mt={0.4}
        style={{ display: 'flex', alignItems: 'center', gap: '0.3em' }}
      >
        <span style={swatchStyle(hex)} />
        <Input
          fluid
          value={hexText}
          onChange={(value) => {
            setHexText(value);
            const parsed = normalizeHex(value);
            if (parsed) setHsva(hexToHsva(parsed));
          }}
        />
        <Button icon="check" onClick={() => onApply(hex)}>
          Apply
        </Button>
      </Box>
    </Box>
  );
};

/// One colour: a swatch that opens its popover. The popover offers the palette's colours and Custom, a picker in
/// place. `onLink`, for a field that can follow a slot, links it to the slot picked (the slot it follows, `linked`,
/// is highlighted); without it a slot's colour is copied through `onPick`, which also takes the custom colour.
export const ColorSwatch = ({
  color,
  label,
  onPick,
  onLink,
  linked,
  showHex,
  extra,
}: {
  color: string;
  label?: string;
  /// Unused: the curated sets are gone.
  category?: string;
  onPick: (hex: string) => void;
  onLink?: (slot: SlotName) => void;
  linked?: SlotName | null;
  /// Unused: Custom picks in place now instead of opening BYOND's picker.
  onCustom?: () => void;
  showHex?: boolean;
  /// Extra rows for the popover (e.g. a pref's "unset" action).
  extra?: ReactNode;
}) => {
  const { slots } = useColorTools();
  const hex = normalizeHex(color) ?? '#000000';
  const [open, setOpen] = useState(false);
  const [custom, setCustom] = useState(false);
  const setOpenState = (value: boolean) => {
    setOpen(value);
    if (!value) setCustom(false);
  };
  const pickedSlot = linked ?? null;
  const customSelected = onLink ? !pickedSlot : true;
  return (
    <Floating
      placement="bottom-start"
      handleOpen={open}
      onOpenChange={setOpenState}
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
        <Box
          onKeyDown={(e) => {
            if (e.key === 'Escape') setOpenState(false);
          }}
        >
          {label && (
            <Box bold mb={0.3}>
              {label}
            </Box>
          )}
          <Box color="label" fontSize="0.85em" mb={0.2}>
            Palette
          </Box>
          <Box
            style={{
              display: 'flex',
              gap: '0.3em',
              marginBottom: '0.4em',
            }}
          >
            {PALETTE_SLOTS.map(({ slot, label: slotLabel }) => {
              const slotHex = slots[slot] ?? '#000000';
              const selected = onLink
                ? pickedSlot === slot
                : normalizeHex(slotHex) === hex;
              return (
                <span
                  key={slot}
                  className="dq-slot-dot"
                  title={onLink ? `Link to ${slotLabel}` : slotLabel}
                  onClick={() => {
                    if (onLink) onLink(slot);
                    else onPick(slotHex);
                    setOpenState(false);
                  }}
                  style={{
                    ...swatchStyle(slotHex, 1.25),
                    borderRadius: '50%',
                    cursor: 'pointer',
                    outline: selected ? '0.15em solid #fff' : undefined,
                    outlineOffset: '0.08em',
                  }}
                />
              );
            })}
          </Box>
          <Button
            fluid
            icon="eye-dropper"
            selected={custom || (customSelected && !!onLink)}
            onClick={() => setCustom((v) => !v)}
          >
            Custom
          </Button>
          {custom && (
            <InlineColorPicker
              initial={hex}
              onApply={(picked) => {
                onPick(picked);
                setOpenState(false);
              }}
            />
          )}
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
      onPick={(hex) =>
        act('dq_update_preference', { key: prefKey, value: hex })
      }
    />
  );
};

export type StripColor = { key: string; label: string };

/// A colour field: the five slot dots plus Custom. `link` is the slot it follows, if any. `onLink` links it,
/// `onPick` gives it a colour of its own (Custom picks it in place). While a slot is the brush, a click
/// anywhere on the field assigns that slot.
export const ColorChoice = ({
  color,
  link,
  label,
  onLink,
  onPick,
  compact,
}: {
  color: string;
  link?: string;
  label?: string;
  /// Unused: the curated sets are gone.
  category?: string;
  onLink: (slot: SlotName) => void;
  onPick: (hex: string) => void;
  /// Unused: Custom picks in place now instead of opening BYOND's picker.
  onCustom?: () => void;
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
          cursor: brush ? 'copy' : undefined,
        }}
      >
        <ColorSwatch
          color={hex}
          onPick={onPick}
          onLink={onLink}
          linked={linked}
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
        <ColorSwatch color={hex} label="Custom" onPick={onPick} />
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
            compact={compact}
            onLink={(slot) =>
              act('dq_update_preference', { key: c.key, value: slot })
            }
            onPick={(hex) =>
              act('dq_update_preference', { key: c.key, value: hex })
            }
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
              minWidth: compact ? '9em' : '14em',
              flex: compact ? '1 1 9em' : '1 1 14em',
            }}
          >
            <Box color="label" fontSize="0.85em" style={{ flex: '0 0 auto' }}>
              {a.label}
            </Box>
            <Box style={{ flex: 1, minWidth: '6em', fontSize: '1.15em' }}>
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
