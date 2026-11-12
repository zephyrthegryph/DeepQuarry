// DQAdd — Antag opt-in editor. Renders be_special as a grid of toggle buttons.

import { useBackend } from 'tgui/backend';
import { Box, Button } from 'tgui-core/components';
import type { EditorProps } from './index';

export const AntagOptInEditor = ({
  data: d,
  staticData: s,
}: EditorProps<'antag_optin'>) => {
  const { act } = useBackend();
  const labels = s?.labels ?? {};
  const keys = Object.keys(labels);
  return (
    <Box
      style={{
        display: 'grid',
        gridTemplateColumns:
          'repeat(auto-fit, minmax(min(100%, 18.333em), 1fr))',
        gap: '0.333em',
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
