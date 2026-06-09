// DQAdd — Antag opt-in editor. Renders be_special as a grid of toggle buttons.

import { useBackend } from 'tgui/backend';
import { Box, Button } from 'tgui-core/components';
import type { EditorProps } from './index';

type Data = { flags: Record<string, boolean> };
type Static = { labels: Record<string, string> };

export const AntagOptInEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as Data;
  const s = (staticData ?? {}) as Static;
  const labels = s.labels ?? {};
  const keys = Object.keys(labels);
  return (
    <Box
      style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
        gap: '4px',
      }}
    >
      {keys.map((flag) => {
        const on = !!d.flags?.[flag];
        return (
          <Button
            key={flag}
            fluid
            selected={on}
            color={on ? 'good' : undefined}
            icon={on ? 'square-check' : 'square'}
            onClick={() =>
              act('dq_editor_action', {
                editor: 'antag_optin',
                action: 'toggle_flag',
                params: { flag },
              })
            }
          >
            {labels[flag] ?? flag}
          </Button>
        );
      })}
    </Box>
  );
};
