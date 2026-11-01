// DQAdd — Organs / cybernetics editor. External limbs and internal organs render
// in a 2-column grid (externals left, internals right) so the page fits without
// scrolling at the standard window size. Each row is a tight flex line with
// label + button row + (for externals) model dropdown.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Box, Button, Dropdown } from 'tgui-core/components';
import type { EditorProps } from './index';

type ExternalState = {
  status: 'normal' | 'amputated' | 'cyborg';
  model?: string | null;
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

/// Which values of `order` differ from `normal`, named, for a one-line summary.
export const summarize = (
  order: string[],
  labels: Record<string, string>,
  isChanged: (key: string) => boolean,
  allNormal: string,
): string => {
  const changed = order.filter(isChanged).map((k) => labels[k] ?? k);
  return changed.length ? `Changed: ${changed.join(', ')}` : allNormal;
};

const rowStyle = (changed: boolean, focused: boolean) => ({
  display: 'flex',
  alignItems: 'center',
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
  const [organsOpen, setOrgansOpen] = useState(false);

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
  const shownOrgans = organsOpen
    ? internalOrder
    : internalOrder.filter((o) => organOf(o) !== 'normal');

  return (
    <Box>
      <Box color="label" mb={0.3}>
        {summarize(
          externalOrder,
          externalLabels,
          (l) => statusOf(l) !== 'normal',
          'All limbs normal',
        )}
      </Box>
      <Box
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 22em), 1fr))',
          gap: '0.1em 0.8em',
        }}
      >
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
                options={EXTERNAL_STATES.map((o) => ({
                  value: o.key,
                  displayText: o.label,
                }))}
                onSelected={(v) =>
                  send('set_external_status', { limb, status: String(v) })
                }
              />
              {state.status === 'cyborg' && limbModels.length > 0 && (
                <Box style={{ flex: 1, minWidth: 0 }}>
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
      <Box
        mt={0.6}
        mb={0.3}
        style={{ display: 'flex', alignItems: 'center', gap: '0.5em' }}
      >
        <Button
          compact
          icon={organsOpen ? 'chevron-down' : 'chevron-right'}
          onClick={() => setOrgansOpen(!organsOpen)}
        >
          Organs
        </Button>
        <Box color="label">
          {summarize(
            internalOrder,
            internalLabels,
            (o) => organOf(o) !== 'normal',
            'All organs normal',
          )}
        </Box>
      </Box>
      <Box
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 22em), 1fr))',
          gap: '0.1em 0.8em',
        }}
      >
        {shownOrgans.map((organ) => (
          <Box key={organ} style={rowStyle(organOf(organ) !== 'normal', false)}>
            <Box style={{ flex: '0 0 6em' }}>
              {internalLabels[organ] ?? organ}
            </Box>
            <Dropdown
              width="8em"
              selected={organOf(organ)}
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
