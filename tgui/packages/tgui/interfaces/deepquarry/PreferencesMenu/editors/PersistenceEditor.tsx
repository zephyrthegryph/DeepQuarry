// DQAdd — Persistence settings editor. Renders persistence_settings as a grid of
// toggle buttons, one per PERSIST_* flag. Each toggle round-trips through
// /datum/preference_editor/persistence.

import { useBackend } from 'tgui/backend';
import { Box, Button } from 'tgui-core/components';
import type { EditorProps } from './index';

type Data = {
  flags: Record<string, boolean>;
};

type Static = {
  labels: Record<string, string>;
};

export const PersistenceEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as Data;
  const s = (staticData ?? {}) as Static;
  const labels = s.labels ?? {};
  const flagOrder = ['spawn', 'weight', 'organs', 'markings', 'size'];
  return (
    <Box
      style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
        gap: '4px',
      }}
    >
      {flagOrder.map((flag) => {
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
                editor: 'persistence',
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
