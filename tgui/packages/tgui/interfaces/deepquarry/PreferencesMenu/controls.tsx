// DQAdd — the character setup's one control per kind. PrefWidget picks among these centrally
// (see resolveWidget there), and editors with the same kind of setting use the same control:
//   on/off            -> Switch
//   2-4 short choices -> Segmented
//   long choice lists -> SearchableDropdown
//   numbers           -> SliderBox (slider plus a typed box)
// Every size is in em so the controls follow the theme font and the display scale.

import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Box,
  Button,
  Floating,
  Input,
  NumberInput,
  Slider,
} from 'tgui-core/components';

/// An on/off switch: a pill with a knob, and the state written beside it.
export const Switch = ({
  checked,
  onToggle,
  label,
  disabled,
  tooltip,
}: {
  checked: boolean;
  onToggle: () => void;
  /// Text beside the switch; defaults to Yes/No.
  label?: string;
  disabled?: boolean;
  tooltip?: string;
}) => (
  <span
    role="switch"
    aria-checked={checked}
    tabIndex={disabled ? -1 : 0}
    title={tooltip}
    className="dq-switch"
    onClick={() => !disabled && onToggle()}
    onKeyDown={(e) => {
      if (!disabled && (e.key === ' ' || e.key === 'Enter')) {
        e.preventDefault();
        onToggle();
      }
    }}
    style={{
      display: 'inline-flex',
      alignItems: 'center',
      gap: '0.45em',
      cursor: disabled ? 'default' : 'pointer',
      opacity: disabled ? 0.5 : 1,
      userSelect: 'none',
      maxWidth: '100%',
    }}
  >
    <span
      style={{
        position: 'relative',
        flex: '0 0 auto',
        width: '2.3em',
        height: '1.25em',
        borderRadius: '0.625em',
        background: checked ? 'var(--color-good, #5baa27)' : '#3b3b3b',
        border: '0.0833em solid rgba(255,255,255,0.25)',
        transition: 'background 0.12s',
      }}
    >
      <span
        style={{
          position: 'absolute',
          top: '0.1em',
          left: checked ? '1.15em' : '0.1em',
          width: '0.9em',
          height: '0.9em',
          borderRadius: '50%',
          background: '#eee',
          transition: 'left 0.12s',
        }}
      />
    </span>
    <span style={{ overflowWrap: 'anywhere' }}>
      {label ?? (checked ? 'Yes' : 'No')}
    </span>
  </span>
);

/// A row of joined buttons, one of which is selected.
export const Segmented = ({
  options,
  value,
  onSelect,
}: {
  options: Array<[string, string]>;
  value: string;
  onSelect: (value: string) => void;
}) => (
  <Box
    style={{
      display: 'inline-flex',
      flexWrap: 'wrap',
      gap: '0.15em',
      maxWidth: '100%',
    }}
  >
    {options.map(([val, label]) => (
      <Button
        key={val}
        m={0}
        selected={val === value}
        onClick={() => val !== value && onSelect(val)}
      >
        {label}
      </Button>
    ))}
  </Box>
);

/// A dropdown with a filter box, for choice lists too long to scan (more than a screenful).
export const SearchableDropdown = ({
  options,
  value,
  onSelect,
  placeholder,
}: {
  options: Array<[string, string]>;
  value: string;
  onSelect: (value: string) => void;
  placeholder?: string;
}) => {
  const [open, setOpen] = useState(false);
  const [filter, setFilter] = useState('');
  const current = options.find(([v]) => v === value)?.[1] ?? value;
  const lc = filter.trim().toLowerCase();
  const shown = useMemo(
    () =>
      lc
        ? options.filter(
            ([v, l]) =>
              l.toLowerCase().includes(lc) || v.toLowerCase().includes(lc),
          )
        : options,
    [options, lc],
  );
  return (
    <Floating
      placement="bottom-start"
      contentAutoWidth
      onOpenChange={(o) => {
        setOpen(o);
        if (!o) setFilter('');
      }}
      contentStyles={{
        zIndex: 60,
        background: 'var(--color-base, #252525)',
        border: '0.0833em solid rgba(255,255,255,0.2)',
        borderRadius: '0.2em',
        boxShadow: '0 0.3em 1em rgba(0,0,0,0.6)',
        padding: '0.3em',
        minWidth: '14em',
      }}
      content={
        <Box>
          <Input
            fluid
            autoFocus
            placeholder={placeholder ?? 'Filter…'}
            value={filter}
            onChange={setFilter}
            onEnter={() => {
              if (shown[0]) {
                onSelect(shown[0][0]);
                setOpen(false);
              }
            }}
          />
          <Box mt={0.3} style={{ maxHeight: '18em', overflowY: 'auto' }}>
            {shown.length === 0 && (
              <Box color="label" italic p={0.3}>
                No matches.
              </Box>
            )}
            {shown.map(([val, label]) => (
              <Button
                key={val}
                fluid
                color="transparent"
                selected={val === value}
                onClick={() => onSelect(val)}
              >
                {label}
              </Button>
            ))}
          </Box>
        </Box>
      }
      closeAfterInteract
    >
      <Box
        className="Button Button--color--default"
        style={{
          display: 'flex',
          alignItems: 'center',
          width: '100%',
          minWidth: 0,
          cursor: 'pointer',
        }}
      >
        <Box
          style={{
            flex: 1,
            minWidth: 0,
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
          }}
        >
          {current || '—'}
        </Box>
        <Box
          as="span"
          ml={0.5}
          className={`fa fa-chevron-${open ? 'up' : 'down'}`}
        />
      </Box>
    </Floating>
  );
};

/// Step 0.1 → 1 decimal; 0.01 → 2; 1 → 0.
export function decimalsForStep(step: number): number {
  if (!Number.isFinite(step) || step <= 0 || step >= 1) return 0;
  const s = step.toString();
  const dotIdx = s.indexOf('.');
  return dotIdx < 0 ? 0 : s.length - dotIdx - 1;
}

export function roundTo(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

/// A number: a slider for feel and a box for an exact value, sharing one buffered value.
/// The server value is ignored while the player drags or types, and the new value is sent once
/// they let go (the ~1 Hz poll would otherwise yank the thumb back mid-drag).
export const SliderBox = ({
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
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    if (!interacting.current) setLocal(serverValue);
  }, [serverValue]);
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );
  const change = (v: number) => {
    interacting.current = true;
    const rounded = roundTo(Math.min(max, Math.max(min, v)), decimals);
    setLocal(rounded);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      interacting.current = false;
      if (rounded !== serverValue) onCommit(rounded);
    }, 150);
  };
  return (
    <Box style={{ display: 'flex', alignItems: 'center', gap: '0.4em' }}>
      <Box style={{ flex: 1, minWidth: '4em' }}>
        <Slider
          minValue={min}
          maxValue={max}
          step={step}
          value={local}
          format={() => ''}
          animated={false}
          tickWhileDragging
          onChange={(_, v) => change(v)}
        />
      </Box>
      <Box
        style={{
          flex: '0 0 auto',
          width: '5.5em',
        }}
      >
        <NumberInput
          fluid
          value={local}
          minValue={min}
          maxValue={max}
          step={step}
          format={format}
          animated={false}
          onChange={(v) => change(v)}
        />
      </Box>
    </Box>
  );
};
