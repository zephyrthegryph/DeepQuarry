// DQAdd — Auto-renders a single /datum/preference widget. The DM side picks the widget
// type via /datum/preference.get_widget(); this component dispatches to the right control.

import { useEffect, useRef, useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  ColorBox,
  Dropdown,
  Input,
  NumberInput,
  Slider,
  Stack,
  TextArea,
} from 'tgui-core/components';
import {
  ColorizedImage,
  ColorizedImageButton,
} from './helper_components';
import type { PrefWidgetItem } from './types';

type Props = { item: PrefWidgetItem };

const sendUpdate = (act: ReturnType<typeof useBackend>['act'], key: string, value: unknown) => {
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

/// Slider that buffers server value vs. local drag state. tgui-core's Slider
/// fires onChange only on release. We track local value via tickWhileDragging
/// → keep our useState in sync with the user's drag position, and commit
/// only when the user releases (delta vs. last-committed serverValue).
/// Server-side value updates during drag are ignored so the thumb doesn't
/// snap mid-drag.
const BufferedSlider = ({
  serverValue,
  min,
  max,
  step,
  onCommit,
}: {
  serverValue: number;
  min: number;
  max: number;
  step: number;
  onCommit: (v: number) => void;
}) => {
  const decimals = decimalsForStep(step);
  const format = (v: number) => v.toFixed(decimals);
  const [local, setLocal] = useState(serverValue);
  const interacting = useRef(false);
  // Sync to server value only when the user isn't currently interacting.
  // Without this guard, a poll-time push of the previous value would yank
  // the thumb back mid-drag and cause the cursor/thumb mismatch.
  useEffect(() => {
    if (!interacting.current) setLocal(serverValue);
  }, [serverValue]);
  // tickWhileDragging makes onChange fire as the user drags. We use that to
  // update local state and mark interacting=true. We can't tell drag-end from
  // a normal commit just from event types; instead we mark not-interacting on
  // a short timeout after the last tick, which is when the user has released.
  const interactionTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  return (
    <Slider
      minValue={min}
      maxValue={max}
      step={step}
      value={local}
      format={format}
      animated={false}
      tickWhileDragging
      onChange={(_, v) => {
        interacting.current = true;
        const rounded = roundTo(v, decimals);
        setLocal(rounded);
        if (interactionTimer.current) clearTimeout(interactionTimer.current);
        interactionTimer.current = setTimeout(() => {
          interacting.current = false;
          if (rounded !== serverValue) onCommit(rounded);
        }, 120);
      }}
    />
  );
};

const BufferedNumberInput = ({
  serverValue,
  min,
  max,
  step,
  onCommit,
}: {
  serverValue: number;
  min: number;
  max: number;
  step: number;
  onCommit: (v: number) => void;
}) => {
  const decimals = decimalsForStep(step);
  const format = (v: number) => v.toFixed(decimals);
  const [local, setLocal] = useState(serverValue);
  const interacting = useRef(false);
  useEffect(() => {
    if (!interacting.current) setLocal(serverValue);
  }, [serverValue]);
  const interactionTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  return (
    <NumberInput
      fluid
      value={local}
      minValue={min}
      maxValue={max}
      step={step}
      format={format}
      animated={false}
      onChange={(v) => {
        interacting.current = true;
        const rounded = roundTo(v, decimals);
        setLocal(rounded);
        if (interactionTimer.current) clearTimeout(interactionTimer.current);
        interactionTimer.current = setTimeout(() => {
          interacting.current = false;
          if (rounded !== serverValue) onCommit(rounded);
        }, 120);
      }}
    />
  );
};

export const PrefWidget = ({ item }: Props) => {
  const { act } = useBackend();

  switch (item.widget) {
    case 'text':
      // BufferedInput: buffers locally and flushes on blur/Enter. Without buffering, the
      // ~1Hz tgui poll lands between keystrokes and yanks the caret position; the user
      // ends up retyping. Same pattern VoreMessagesEditor uses for its own draft.
      //
      // Width is unconstrained so the input fills its grid cell — the WidgetGrid in
      // CategoryPage caps each cell at the column width.
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
        <BufferedNumberInput
          serverValue={Number(item.value ?? min)}
          min={min}
          max={max}
          step={step}
          onCommit={(v) => sendUpdate(act, item.key, v)}
        />
      );
    }
    case 'slider': {
      const min = Number((item.props.min as number | undefined) ?? 0);
      const max = Number((item.props.max as number | undefined) ?? 100);
      const step = Number((item.props.step as number | undefined) ?? 1);
      return (
        <BufferedSlider
          serverValue={Number(item.value ?? min)}
          min={min}
          max={max}
          step={step}
          onCommit={(v) => sendUpdate(act, item.key, v)}
        />
      );
    }

    case 'boolean':
      return (
        <Button
          selected={!!item.value}
          icon={item.value ? 'check' : 'xmark'}
          onClick={() => sendUpdate(act, item.key, !item.value)}
        >
          {item.value ? 'Yes' : 'No'}
        </Button>
      );

    case 'color': {
      const hex = String(item.value ?? '#000000');
      // Color picking is a BYOND-side modal — tgui-core has no native color input. Fire
      // dq_pick_color and let the DM middleware open tgui_color_picker; the resulting
      // write comes back through the normal data-poll flow.
      return (
        <Stack align="center">
          <Stack.Item>
            <ColorBox color={hex} />
          </Stack.Item>
          <Stack.Item>
            <Button
              onClick={() => act('dq_pick_color', { key: item.key })}
            >
              {hex}
            </Button>
          </Stack.Item>
        </Stack>
      );
    }

    case 'dropdown': {
      const choices = normalizeChoices(item.choices);
      const options = choices.map(([val, label]) => ({ value: val, displayText: label }));
      const currentVal = String(item.value ?? '');
      // tgui-core Dropdown doesn't look up the option label from the value on its own —
      // if `selected` is a string it just renders that string. Override with displayText.
      const currentLabel =
        options.find((o) => o.value === currentVal)?.displayText ?? currentVal;
      // `fluid` is the supported way to make Dropdown fill its container width;
      // `width="100%"` is documented as deprecated/layout-breaking in tgui-core.
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
    case 'radio': {
      const choices = normalizeChoices(item.choices);
      return (
        <Stack wrap>
          {choices.map(([val, label]) => (
            <Stack.Item key={val}>
              <Button
                selected={item.value === val}
                onClick={() => sendUpdate(act, item.key, val)}
              >
                {label}
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      );
    }

    case 'multi': {
      const selected = Array.isArray(item.value) ? (item.value as string[]) : [];
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
          onPick={(val) => sendUpdate(act, item.key, val)}
        />
      );

    case 'hidden':
    case 'editor':
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

function normalizeChoices(
  choices: PrefWidgetItem['choices'],
): Array<[string, string]> {
  if (!choices) return [];
  if (Array.isArray(choices)) {
    return choices.map((v) => [v, v]);
  }
  return Object.entries(choices);
}

/// Step 0.1 → 1 decimal; 0.01 → 2; 1 → 0. JS floats can produce 0.7000000000000001
/// during slider arithmetic; we use toFixed(decimals) for display + roundTo for the
/// wire value so the savefile doesn't get a bunch of phantom decimals.
function decimalsForStep(step: number): number {
  if (!Number.isFinite(step) || step <= 0) return 0;
  if (step >= 1) return 0;
  const s = step.toString();
  const dotIdx = s.indexOf('.');
  if (dotIdx < 0) return 0;
  return s.length - dotIdx - 1;
}

function roundTo(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

/// Inline thumbnail picker. The Change button toggles a panel that expands
/// inline below the trigger row, scoped to the widget's grid cell — no
/// full-window Dimmer overlay. The panel has its own scroll for long lists
/// of thumbnails (hair/marking catalogs run into the hundreds of entries).
const ThumbgridPicker = ({
  item,
  onPick,
}: {
  item: PrefWidgetItem;
  onPick: (val: string) => void;
}) => {
  const choices = normalizeChoices(item.choices);
  const thumbs = item.thumbnails ?? {};
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const currentVal = String(item.value ?? '');
  const currentThumb = thumbs[currentVal];
  // Display the user-facing label for the current selection, not the raw value
  // (which is the asset key — e.g. "marking_arrow_chest" instead of "Chest Arrow").
  const currentLabel =
    choices.find(([val]) => val === currentVal)?.[1] ?? currentVal;

  const lcSearch = search.trim().toLowerCase();
  const filtered = choices.filter(
    ([val, label]) =>
      !lcSearch ||
      val.toLowerCase().includes(lcSearch) ||
      label.toLowerCase().includes(lcSearch),
  );

  return (
    <Box style={{ width: '100%' }}>
      <Stack align="center">
        {currentThumb ? (
          <Stack.Item>
            <ColorizedImage
              iconRef={currentThumb.icon}
              iconState={currentThumb.icon_state}
              color="#ffffff"
              size={32}
            />
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
        <Stack.Item>
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
            borderRadius: '4px',
            border: '1px solid rgba(255,255,255,0.1)',
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
          <Box style={{ maxHeight: '260px', overflowY: 'auto' }}>
            <Stack wrap>
              {filtered.map(([val, label]) => {
                const t = thumbs[val];
                return (
                  <Stack.Item key={val} m={0.25}>
                    {t ? (
                      <ColorizedImageButton
                        iconRef={t.icon}
                        iconState={t.icon_state}
                        color="#ffffff"
                        tooltip={label}
                        selected={val === currentVal}
                        onClick={() => {
                          onPick(val);
                          setOpen(false);
                        }}
                      >
                        {label}
                      </ColorizedImageButton>
                    ) : (
                      <Button
                        selected={val === currentVal}
                        onClick={() => {
                          onPick(val);
                          setOpen(false);
                        }}
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
    </Box>
  );
};
