// DQAdd — Persistence settings editor. Renders persistence_settings as a grid of
// toggle buttons, one per PERSIST_* flag. Each toggle round-trips through
// /datum/preference_editor/persistence.

import { useBackend } from 'tgui/backend';
import { Box } from 'tgui-core/components';
import { Switch } from '../controls';
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
        gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 16em), 1fr))',
        gap: '0.35em 1em',
      }}
    >
      {flagOrder.map((flag) => (
        <Switch
          key={flag}
          checked={!!d.flags?.[flag]}
          label={labels[flag] ?? flag}
          onToggle={() =>
            act('dq_editor_action', {
              editor: 'persistence',
              action: 'toggle_flag',
              params: { flag },
            })
          }
        />
      ))}
    </Box>
  );
};
