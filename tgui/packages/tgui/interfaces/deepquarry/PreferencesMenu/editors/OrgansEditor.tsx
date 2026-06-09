// DQAdd — Organs / cybernetics editor. External limbs and internal organs render
// in a 2-column grid (externals left, internals right) so the page fits without
// scrolling at the standard window size. Each row is a tight flex line with
// label + button row + (for externals) model dropdown.

import { useBackend } from 'tgui/backend';
import { Box, Button, Dropdown } from 'tgui-core/components';
import type { EditorProps } from './index';

type ExternalState = { status: 'normal' | 'amputated' | 'cyborg'; model?: string | null };
type Data = {
  externals: Record<string, ExternalState>;
  internals: Record<string, string>;
};

type Static = {
  external_labels: Record<string, string>;
  internal_labels: Record<string, string>;
  limb_models: string[];
  external_order: string[];
  internal_order: string[];
};

const EXTERNAL_STATES: Array<{ key: 'normal' | 'amputated' | 'cyborg'; label: string; color?: string }> = [
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

export const OrgansEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as Data;
  const s = (staticData ?? {}) as Static;

  const send = (action: string, params: Record<string, unknown>) =>
    act('dq_editor_action', { editor: 'organs', action, params });

  const externalOrder = s.external_order ?? Object.keys(s.external_labels ?? {});
  const internalOrder = s.internal_order ?? Object.keys(s.internal_labels ?? {});
  const limbModels = s.limb_models ?? [];
  const modelOptions = limbModels.map((m) => ({ value: m, displayText: m }));

  return (
    <Box
      style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(360px, 1fr))',
        gap: '12px',
      }}
    >
      <Box>
        <Box bold mb={0.5} color="label">External Limbs</Box>
        {externalOrder.map((limb) => {
          const state = d.externals?.[limb] ?? { status: 'normal' };
          return (
            <Box
              key={limb}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                padding: '2px 0',
                fontSize: '0.9em',
              }}
            >
              <Box style={{ flex: '0 0 80px' }}>
                {s.external_labels?.[limb] ?? limb}
              </Box>
              <Box style={{ flex: '0 0 auto', display: 'flex', gap: '2px' }}>
                {EXTERNAL_STATES.map((opt) => (
                  <Button
                    key={opt.key}
                    compact
                    selected={state.status === opt.key}
                    color={state.status === opt.key ? opt.color : undefined}
                    onClick={() =>
                      send('set_external_status', { limb, status: opt.key })
                    }
                  >
                    {opt.label}
                  </Button>
                ))}
              </Box>
              <Box style={{ flex: 1, minWidth: 0 }}>
                {state.status === 'cyborg' && limbModels.length > 0 && (
                  <Dropdown
                    width="100%"
                    selected={state.model ?? limbModels[0]}
                    options={modelOptions}
                    onSelected={(v) =>
                      send('set_external_model', { limb, model: String(v) })
                    }
                  />
                )}
              </Box>
            </Box>
          );
        })}
      </Box>
      <Box>
        <Box bold mb={0.5} color="label">Internal Organs</Box>
        {internalOrder.map((organ) => {
          const status = d.internals?.[organ] ?? 'normal';
          return (
            <Box
              key={organ}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                padding: '2px 0',
                fontSize: '0.9em',
              }}
            >
              <Box style={{ flex: '0 0 100px' }}>
                {s.internal_labels?.[organ] ?? organ}
              </Box>
              <Box style={{ flex: 1, display: 'flex', gap: '2px' }}>
                {INTERNAL_STATES.map((opt) => (
                  <Button
                    key={opt.key}
                    compact
                    selected={status === opt.key}
                    color={status === opt.key ? opt.color : undefined}
                    onClick={() =>
                      send('set_internal_status', { limb: organ, status: opt.key })
                    }
                  >
                    {opt.label}
                  </Button>
                ))}
              </Box>
            </Box>
          );
        })}
      </Box>
    </Box>
  );
};
