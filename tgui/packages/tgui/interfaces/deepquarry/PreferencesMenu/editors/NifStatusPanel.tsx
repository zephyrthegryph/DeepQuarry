// DQAdd — Read-only NIF state display.

import { Box } from 'tgui-core/components';
import type { EditorProps } from './index';

type NifData = {
  installed: boolean;
  nif_type: string | null;
  display_name: string | null;
  durability: number | null;
};

export const NifStatusPanel = ({ data }: EditorProps) => {
  const d = data as NifData;
  if (!d.installed) {
    return <Box italic>No NIF installed.</Box>;
  }
  return (
    <Box>
      <Box>
        Installed: <b>{d.display_name ?? d.nif_type}</b>
      </Box>
      <Box>
        Durability: <b>{d.durability ?? '—'}</b>
      </Box>
      <Box italic mt={1}>
        Configure NIFsoft via the NIF item's own interface in-game.
      </Box>
    </Box>
  );
};
