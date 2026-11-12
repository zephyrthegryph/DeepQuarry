import { useBackend } from 'tgui/backend';
import { Box, Button, Icon, Input } from 'tgui-core/components';

import { FullscreenNotice } from '../common/FullscreenNotice';
import type { MessageMonitorActions } from '../generated/MessageMonitor';
import type { Data } from './types';
import { Label } from 'tgui/components/Label';

export const MessageMonitorLogin = (props) => {
  const { act, data } = useBackend<Data, MessageMonitorActions>();

  const { isMalfAI } = data;

  return (
    <FullscreenNotice title="Welcome">
      <Box fontSize="1.5rem" bold>
        <Icon
          name="exclamation-triangle"
          verticalAlign="middle"
          size={3}
          mr="1rem"
        />
        Unauthorized
      </Box>
      <Label my="1rem">
        Decryption Key:
        <Input
          placeholder="Decryption Key"
          ml="0.5rem"
          onBlur={(val) => act('auth', { key: val })}
        />
      </Label>
      {!!isMalfAI && (
        <Button icon="terminal" onClick={() => act('hack')}>
          Hack
        </Button>
      )}
      <Label>
        Please authenticate with the server in order to show additional options.
      </Label>
    </FullscreenNotice>
  );
};
