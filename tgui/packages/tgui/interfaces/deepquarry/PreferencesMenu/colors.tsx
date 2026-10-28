// DQAdd — the character setup's one colour model.
//
//  - ColorSwatch: every colour in the window is a swatch. Clicking it opens a small popover that
//    offers the character's saved palette first, then "Custom…" (BYOND's colour picker) and
//    "Save to palette". The same swatch is used for single colour prefs and for body-part sets.
//  - ColorStrip: a body part's colours (primary/secondary/tertiary) plus its opacity on one line,
//    with copy/paste of the whole set between parts and "match skin"/"match hair" links.
//  - PaletteEditor: the per-character palette itself (the color_palette preference).
//
// The palette and the copy buffer reach every swatch through ColorToolsContext, which
// DQCharacterSetup fills from the cached values.

import { createContext, type ReactNode, useContext, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Box, Button, Floating, Input } from 'tgui-core/components';
import { SliderBox } from './controls';
import { prefAnchor, highlightStyle, useSearchHighlight } from './search';

export const PALETTE_KEY = 'color_palette';
export const PALETTE_MAX = 8;

export type ColorTools = {
  palette: string[];
  /// The colours of the last "copy" (a part's set), shared by every strip.
  clipboard: string[] | null;
  setClipboard: (colors: string[] | null) => void;
  /// Named colours a strip can match ("Skin" -> the skin colour).
  references: Record<string, string>;
};

export const ColorToolsContext = createContext<ColorTools>({
  palette: [],
  clipboard: null,
  setClipboard: () => {},
  references: {},
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

export const paletteFromValue = (value: unknown): string[] =>
  Array.isArray(value)
    ? (value.map(normalizeHex).filter(Boolean) as string[]).slice(
        0,
        PALETTE_MAX,
      )
    : [];

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

/// One colour: a swatch that opens the picker popover. `onPick` writes a colour directly
/// (palette entry or paste); `onCustom` opens BYOND's own colour picker.
export const ColorSwatch = ({
  color,
  label,
  onPick,
  onCustom,
  showHex,
  extra,
}: {
  color: string;
  label?: string;
  onPick: (hex: string) => void;
  onCustom: () => void;
  showHex?: boolean;
  /// Extra rows for the popover (e.g. a pref's "unset" action).
  extra?: ReactNode;
}) => {
  const { act } = useBackend();
  const { palette } = useColorTools();
  const hex = normalizeHex(color) ?? '#000000';
  const inPalette = palette.includes(hex);
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
          <Box color="label" fontSize="0.85em" mb={0.2}>
            Palette
          </Box>
          <Box
            style={{
              display: 'flex',
              flexWrap: 'wrap',
              gap: '0.25em',
              marginBottom: '0.4em',
            }}
          >
            {palette.length === 0 && (
              <Box color="label" italic fontSize="0.85em">
                Empty: save colours here to reuse them on every part.
              </Box>
            )}
            {palette.map((p) => (
              <span
                key={p}
                title={p}
                onClick={() => onPick(p)}
                style={{
                  ...swatchStyle(p, 1.5),
                  cursor: 'pointer',
                  outline: p === hex ? '0.12em solid #fff' : undefined,
                }}
              />
            ))}
          </Box>
          <Button fluid icon="eye-dropper" onClick={onCustom}>
            Custom…
          </Button>
          <Button
            fluid
            icon="bookmark"
            disabled={inPalette || palette.length >= PALETTE_MAX}
            tooltip={
              palette.length >= PALETTE_MAX
                ? `The palette holds ${PALETTE_MAX} colours; remove one first.`
                : undefined
            }
            onClick={() =>
              act('dq_update_preference', {
                key: PALETTE_KEY,
                value: [...palette, hex],
              })
            }
          >
            {inPalette ? 'In palette' : 'Save to palette'}
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
          <span style={{ fontSize: '0.85em', color: 'var(--color-label)' }}>
            {label}
          </span>
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
      onCustom={() => act('dq_pick_color', { key: prefKey })}
    />
  );
};

export type StripColor = { key: string; label: string };

/// A body part's colours and opacity on one line, with copy/paste and match links.
export const ColorStrip = ({
  colors,
  alphas,
  values,
  matches,
}: {
  colors: StripColor[];
  /// Opacity prefs (0-255) shown after the swatches.
  alphas?: StripColor[];
  values: Record<string, unknown>;
  /// Reference names from ColorTools.references this strip offers to match ("Skin", "Hair").
  matches?: string[];
}) => {
  const { act } = useBackend();
  const { clipboard, setClipboard, references } = useColorTools();
  const current = colors.map((c) => normalizeHex(values[c.key]) ?? '#000000');
  const write = (key: string, hex: string) =>
    act('dq_update_preference', { key, value: hex });
  return (
    <Box
      style={{
        display: 'flex',
        flexWrap: 'wrap',
        alignItems: 'center',
        gap: '0.35em 0.6em',
      }}
    >
      <Box style={{ display: 'flex', gap: '0.3em', flexWrap: 'wrap' }}>
        {colors.map((c, i) => (
          <SwatchAnchor key={c.key} prefKey={c.key}>
            <ColorSwatch
              color={current[i]}
              label={c.label}
              onPick={(hex) => write(c.key, hex)}
              onCustom={() => act('dq_pick_color', { key: c.key })}
            />
          </SwatchAnchor>
        ))}
      </Box>
      <Box style={{ display: 'flex', gap: '0.15em' }}>
        <Button
          icon="copy"
          color="transparent"
          tooltip="Copy these colours"
          onClick={() => setClipboard(current)}
        >
          Copy set
        </Button>
        <Button
          icon="paste"
          color="transparent"
          disabled={!clipboard}
          tooltip={
            clipboard
              ? `Paste ${clipboard.join(' ')}`
              : 'Copy a colour set first'
          }
          onClick={() => {
            if (!clipboard) return;
            colors.forEach((c, i) => {
              const hex = clipboard[Math.min(i, clipboard.length - 1)];
              if (hex && hex !== current[i]) write(c.key, hex);
            });
          }}
        >
          Paste set
        </Button>
        {(matches ?? [])
          .filter((name) => references[name])
          .map((name) => (
            <Button
              key={name}
              color="transparent"
              tooltip={`Set the ${colors[0]?.label.toLowerCase() ?? 'first'} colour to the ${name.toLowerCase()} colour (${references[name]})`}
              onClick={() =>
                colors[0] && write(colors[0].key, references[name])
              }
            >
              <span style={swatchStyle(references[name], 0.8)} /> Match{' '}
              {name.toLowerCase()}
            </Button>
          ))}
      </Box>
      {(alphas ?? []).map((a) => (
        <SwatchAnchor key={a.key} prefKey={a.key} grow>
          <Box
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.4em',
              minWidth: '12em',
              flex: '1 1 12em',
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

/// The color_palette preference: the character's saved colours. Add by hex, remove by clicking ×.
export const PaletteEditor = ({ value }: { value: unknown }) => {
  const { act } = useBackend();
  const palette = paletteFromValue(value);
  const [draft, setDraft] = useState('');
  const draftHex = normalizeHex(draft);
  const write = (next: string[]) =>
    act('dq_update_preference', { key: PALETTE_KEY, value: next });
  const add = () => {
    if (!draftHex || palette.includes(draftHex)) return;
    write([...palette, draftHex]);
    setDraft('');
  };
  return (
    <Box>
      <Box
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '0.35em',
          alignItems: 'center',
        }}
      >
        {palette.map((hex, i) => (
          <Box
            key={hex}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.2em',
              padding: '0.1em 0.2em',
              borderRadius: '0.25em',
              background: 'rgba(255,255,255,0.06)',
            }}
          >
            <span style={swatchStyle(hex, 1.4)} title={hex} />
            <Button
              icon="arrow-left"
              color="transparent"
              disabled={i === 0}
              tooltip="Move left"
              onClick={() => {
                const next = [...palette];
                [next[i - 1], next[i]] = [next[i], next[i - 1]];
                write(next);
              }}
            />
            <Button
              icon="xmark"
              color="transparent"
              tooltip={`Remove ${hex}`}
              onClick={() => write(palette.filter((p) => p !== hex))}
            />
          </Box>
        ))}
        {palette.length < PALETTE_MAX && (
          <Box
            style={{
              display: 'inline-flex',
              gap: '0.25em',
              alignItems: 'center',
            }}
          >
            <Box style={{ width: '6.5em' }}>
              <Input
                fluid
                placeholder="#rrggbb"
                value={draft}
                onChange={setDraft}
                onEnter={add}
              />
            </Box>
            {draftHex && <span style={swatchStyle(draftHex)} />}
            <Button icon="plus" disabled={!draftHex} onClick={add}>
              Add
            </Button>
          </Box>
        )}
      </Box>
      <Box color="label" fontSize="0.85em" mt={0.3}>
        {palette.length}/{PALETTE_MAX} colours. Every colour picker offers these
        first; “Save to palette” in any picker adds its colour.
      </Box>
    </Box>
  );
};
