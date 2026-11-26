// DQAdd — Read-only NIF state display.

import { Box } from 'tgui-core/components';
import type { EditorProps } from './index';

export const NifStatusPanel = ({ data: d }: EditorProps<'nif_status'>) => {
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
    </Box>
  );
};
