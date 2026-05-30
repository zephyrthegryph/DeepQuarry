import type { ReactNode } from 'react';
import { Box, Button } from 'tgui-core/components';

type Props = {
  onClick: () => void;
  label?: ReactNode;
  icon?: string;
  mt?: number;
};

export const BackButton = (props: Props) => {
  const { onClick, label, icon = 'arrow-left', mt = 2 } = props;
  return (
    <Box mt={mt}>
      <Button icon={icon} onClick={onClick}>
        {label ?? 'Return to main menu'}
      </Button>
    </Box>
  );
};
