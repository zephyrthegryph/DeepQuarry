// DQAdd — Organs / cybernetics editor. External limbs and internal organs render in two columns.
// Each row: label, a panel of option buttons, then (for robotic limbs) colour and manufacturer.
// A limb whose parent is amputated is greyed out: it goes with the parent and its saved setting
// is kept but not applied (organs apply hook), so restoring the parent brings it back.

import { useBackend } from 'tgui/backend';
import { Box, Button } from 'tgui-core/components';
import { ColorChoice } from '../colors';
import { optionBar, SearchableDropdown, Segmented } from '../controls';
import type { EditorProps } from './index';

type ExternalState = {
  status: 'normal' | 'amputated' | 'cyborg';
  model?: string | null;
  /// A robotic limb's own tint, and the palette slot it follows if any.
  color?: string | null;
  link?: string;
  own_color?: boolean;
  /// The cybernetic ancestor that rules out Normal for this limb.
  forced_by?: string | null;
  /// The amputated ancestor this limb is lost with.
  lost_via?: string | null;
};
type Data = {
  /// This species' own limbs are robotic: one colour for the whole body.
  robotic_body?: boolean | number;
  body_color?: string;
  body_link?: string;
  externals: Record<string, ExternalState>;
  internals: Record<string, string>;
  external_labels?: Record<string, string>;
  internal_labels?: Record<string, string>;
  external_order?: string[];
  internal_order?: string[];
};

type Static = {
  limb_models?: string[];
};

const EXTERNAL_STATES: Array<{
  key: 'normal' | 'amputated' | 'cyborg';
  label: string;
  color?: string;
}> = [
  { key: 'normal', label: 'Normal' },
  { key: 'amputated', label: 'Amputated', color: 'orange' },
  { key: 'cyborg', label: 'Cybernetic', color: 'olive' },
];

const INTERNAL_STATES: Array<{ key: string; label: string; color?: string }> = [
  { key: 'normal', label: 'Normal' },
  { key: 'assisted', label: 'Assisted', color: 'yellow' },
  { key: 'mechanical', label: 'Mechanical', color: 'olive' },
  { key: 'digital', label: 'Digital', color: 'olive' },
];

const LIST_STYLE = {
  flex: '1 1 100%',
  minWidth: 0,
  display: 'flex',
  flexDirection: 'column',
  gap: '0.1em',
} as const;

/// The row's bar shows the option it is set to; a row at Normal has none.
const rowStyle = (
  states: Array<{ key: string; color?: string }>,
  status: string,
  focused: boolean,
) => ({
  display: 'flex',
  alignItems: 'center',
  flexWrap: 'wrap' as const,
  gap: '0.4em',
  padding: '0.1em 0.3em',
  borderRadius: '0.2em',
  borderLeft: optionBar(
    status === 'normal' ? null : states.find((o) => o.key === status),
  ),
  background: focused ? 'rgba(255,255,255,0.14)' : undefined,
});

const asOptions = (
  states: Array<{ key: string; label: string; color?: string }>,
): Array<[string, string, string?]> =>
  states.map((o) => [o.key, o.label, o.color]);

export const OrgansEditor = ({
  data,
  staticData,
  focusLimb,
}: EditorProps & { focusLimb?: string | null }) => {
  const { act } = useBackend();
  const d = data as Data;
  const s = (staticData ?? {}) as Static;

  const send = (action: string, params: Record<string, unknown>) =>
    act('dq_editor_action', { editor: 'organs', action, params });

  // Rows come from the per-update data; only the robolimb model list is a catalog.
  const externalLabels = d.external_labels ?? {};
  const internalLabels = d.internal_labels ?? {};
  const externalOrder = d.external_order ?? Object.keys(d.externals ?? {});
  const internalOrder = d.internal_order ?? Object.keys(d.internals ?? {});
  const limbModels = s.limb_models ?? [];
  const statusOf = (limb: string) => d.externals?.[limb]?.status ?? 'normal';
  const organOf = (organ: string) => d.internals?.[organ] ?? 'normal';

  return (
    <Box
      style={{
        display: 'flex',
        flexWrap: 'wrap',
        gap: '0.5em 1.5em',
        alignItems: 'flex-start',
      }}
    >
      {!!d.robotic_body && (
        <Box style={{ flex: '1 1 100%' }}>
          <Box bold color="label" mb={0.2}>
            Body colour
          </Box>
          <ColorChoice
            color={d.body_color ?? '#ffffff'}
            link={d.body_link}
            category="other"
            onLink={(slot) =>
              send('set_limb_color', { limb: 'body', color: slot })
            }
            onPick={(hex) =>
              send('set_limb_color', { limb: 'body', color: hex })
            }
            onCustom={() => send('pick_limb_color', { limb: 'body' })}
          />
        </Box>
      )}
      <Box style={LIST_STYLE}>
        <Box bold color="label" mb={0.2}>
          Limbs
        </Box>
        {externalOrder.map((limb) => {
          const state = d.externals?.[limb] ?? { status: 'normal' };
          const lostVia = state.lost_via;
          if (lostVia) {
            const saved = EXTERNAL_STATES.find((o) => o.key === state.status);
            return (
              <Box
                key={limb}
                style={{
                  ...rowStyle(EXTERNAL_STATES, 'normal', focusLimb === limb),
                  opacity: 0.55,
                }}
              >
                <Box style={{ flex: '0 0 6em' }}>
                  {externalLabels[limb] ?? limb}
                </Box>
                <Segmented
                  disabled
                  options={asOptions(EXTERNAL_STATES)}
                  value="amputated"
                  onSelect={() => {}}
                />
                <Box color="label">
                  Lost with {externalLabels[lostVia] ?? lostVia}
                  {state.status !== 'normal' &&
                    ` (saved ${saved?.label ?? state.status}, not applied)`}
                </Box>
              </Box>
            );
          }
          return (
            <Box
              key={limb}
              style={rowStyle(
                EXTERNAL_STATES,
                state.status,
                focusLimb === limb,
              )}
            >
              <Box style={{ flex: '0 0 6em' }}>
                {externalLabels[limb] ?? limb}
              </Box>
              <Segmented
                options={asOptions(EXTERNAL_STATES)}
                value={state.status}
                disabledValues={state.forced_by ? ['normal'] : undefined}
                onSelect={(status) =>
                  send('set_external_status', { limb, status })
                }
              />
              {!!state.forced_by && !!state.own_color && (
                <Button
                  compact
                  icon="link"
                  tooltip={`Follow ${externalLabels[state.forced_by] ?? state.forced_by} again`}
                  onClick={() => send('clear_limb_color', { limb })}
                />
              )}
              {state.status === 'cyborg' && (
                <ColorChoice
                  color={state.color ?? '#ffffff'}
                  link={
                    state.forced_by && !state.own_color ? undefined : state.link
                  }
                  category="other"
                  onLink={(slot) =>
                    send('set_limb_color', { limb, color: slot })
                  }
                  onPick={(hex) => send('set_limb_color', { limb, color: hex })}
                  onCustom={() => send('pick_limb_color', { limb })}
                />
              )}
              {state.status === 'cyborg' && limbModels.length > 0 && (
                <Box style={{ flex: '1 1 10em', minWidth: 0 }}>
                  <SearchableDropdown
                    placeholder="Filter manufacturers…"
                    value={state.model ?? limbModels[0]}
                    options={limbModels.map((m) => [m, m])}
                    onSelect={(model) =>
                      send('set_external_model', { limb, model })
                    }
                  />
                </Box>
              )}
            </Box>
          );
        })}
      </Box>
      <Box style={LIST_STYLE}>
        <Box bold color="label" mb={0.2}>
          Organs
        </Box>
        {internalOrder.map((organ) => (
          <Box
            key={organ}
            style={rowStyle(INTERNAL_STATES, organOf(organ), false)}
          >
            <Box style={{ flex: '0 0 6em' }}>
              {internalLabels[organ] ?? organ}
            </Box>
            <Segmented
              options={asOptions(INTERNAL_STATES)}
              value={organOf(organ)}
              onSelect={(status) =>
                send('set_internal_status', { limb: organ, status })
              }
            />
          </Box>
        ))}
      </Box>
    </Box>
  );
};
