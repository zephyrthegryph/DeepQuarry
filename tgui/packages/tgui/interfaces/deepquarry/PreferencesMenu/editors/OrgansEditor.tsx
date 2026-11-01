// DQAdd — Organs / cybernetics editor. External limbs and internal organs render
// in a 2-column grid (externals left, internals right) so the page fits without
// scrolling at the standard window size. Each row is a tight flex line with
// label + button row + (for externals) model dropdown.

import { useBackend } from 'tgui/backend';
import { Box, Dropdown } from 'tgui-core/components';
import { ColorChoice } from '../colors';
import type { EditorProps } from './index';

type ExternalState = {
  status: 'normal' | 'amputated' | 'cyborg';
  model?: string | null;
  /// A robotic limb's own tint, and the palette slot it follows if any.
  color?: string | null;
  link?: string;
};
type Data = {
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
  flex: '1 1 20em',
  minWidth: 0,
  display: 'flex',
  flexDirection: 'column',
  gap: '0.1em',
} as const;

const rowStyle = (changed: boolean, focused: boolean) => ({
  display: 'flex',
  alignItems: 'center',
  flexWrap: 'wrap',
  gap: '0.4em',
  padding: '0.1em 0.3em',
  borderRadius: '0.2em',
  borderLeft: `0.2em solid ${changed ? '#d9a02b' : 'transparent'}`,
  background: focused ? 'rgba(255,255,255,0.14)' : undefined,
});

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
      <Box style={LIST_STYLE}>
        <Box bold color="label" mb={0.2}>
          Limbs
        </Box>
        {externalOrder.map((limb) => {
          const state = d.externals?.[limb] ?? { status: 'normal' };
          return (
            <Box
              key={limb}
              style={rowStyle(state.status !== 'normal', focusLimb === limb)}
            >
              <Box style={{ flex: '0 0 6em' }}>
                {externalLabels[limb] ?? limb}
              </Box>
              <Dropdown
                width="8em"
                selected={state.status}
                displayText={
                  EXTERNAL_STATES.find((o) => o.key === state.status)?.label
                }
                options={EXTERNAL_STATES.map((o) => ({
                  value: o.key,
                  displayText: o.label,
                }))}
                onSelected={(v) =>
                  send('set_external_status', { limb, status: String(v) })
                }
              />
              {state.status === 'cyborg' && (
                <ColorChoice
                  color={state.color ?? '#ffffff'}
                  link={state.link}
                  category="other"
                  onLink={(slot) =>
                    send('set_limb_color', { limb, color: slot })
                  }
                  onPick={(hex) => send('set_limb_color', { limb, color: hex })}
                  onCustom={() => send('pick_limb_color', { limb })}
                />
              )}
              {state.status === 'cyborg' && limbModels.length > 0 && (
                <Box style={{ flex: '1 1 8em', minWidth: 0 }}>
                  <Dropdown
                    width="100%"
                    selected={state.model ?? limbModels[0]}
                    options={limbModels.map((m) => ({
                      value: m,
                      displayText: m,
                    }))}
                    onSelected={(v) =>
                      send('set_external_model', { limb, model: String(v) })
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
          <Box key={organ} style={rowStyle(organOf(organ) !== 'normal', false)}>
            <Box style={{ flex: '0 0 6em' }}>
              {internalLabels[organ] ?? organ}
            </Box>
            <Dropdown
              width="8em"
              selected={organOf(organ)}
              displayText={
                INTERNAL_STATES.find((o) => o.key === organOf(organ))?.label
              }
              options={INTERNAL_STATES.map((o) => ({
                value: o.key,
                displayText: o.label,
              }))}
              onSelected={(v) =>
                send('set_internal_status', {
                  limb: organ,
                  status: String(v),
                })
              }
            />
          </Box>
        ))}
      </Box>
    </Box>
  );
};
