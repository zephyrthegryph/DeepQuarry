import type { ReactNode } from 'react';
import { Box } from 'tgui-core/components';

type Props = {
  children: ReactNode;
  small?: boolean;
  preserveWhitespace?: boolean;
};

export const Mono = (props: Props) => {
  const { children, small = true, preserveWhitespace } = props;
  return (
    <Box
      style={{
        fontFamily: 'monospace',
        fontSize: small ? '0.85em' : undefined,
        whiteSpace: preserveWhitespace ? 'pre-wrap' : undefined,
      }}
    >
      {children}
    </Box>
  );
};
