import type { ReactNode } from 'react';
import { Label } from 'tgui/components/Label';

type Props = {
  message?: ReactNode;
  children?: ReactNode;
};

export const EmptyState = (props: Props) => {
  const { message, children } = props;
  return <Label italic>{message ?? children}</Label>;
};
