import type { ReactNode } from 'react';
import type { Box } from 'tgui-core/components';
import type { LobbyMenuData } from '../generated/LobbyMenu';

export type LobbyData = LobbyMenuData;

export type LobbyContextType = {
  animationsDisabled: boolean;
  animationsFinished: boolean;
  setModal?: (_: ReactNode | false) => void;
};

export type LobbyButtonProps = React.ComponentProps<typeof Box> & {
  readonly index: number;
  readonly selected?: boolean;
  readonly disabled?: boolean;
  readonly icon?: string;
  readonly tooltip?: string;
};
