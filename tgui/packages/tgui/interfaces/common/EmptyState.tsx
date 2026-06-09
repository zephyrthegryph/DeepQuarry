import type { ReactNode } from 'react';
import { Box } from 'tgui-core/components';

type Props = {
  message?: ReactNode;
  children?: ReactNode;
};

export const EmptyState = (props: Props) => {
  const { message, children } = props;
  return (
    <Box italic color="label">
      {message ?? children}
    </Box>
  );
};
