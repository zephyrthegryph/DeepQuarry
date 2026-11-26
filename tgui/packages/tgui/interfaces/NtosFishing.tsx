import { useBackend } from 'tgui/backend';
import { NtosWindow } from 'tgui/layouts';

import { GameWindow as FishingGame } from './FishingMinigame';
import type {
  NtosFishingActions,
  NtosFishingData,
} from './generated/NtosFishing';

export const NtosFishing = (props) => {
  const { act, data } = useBackend<NtosFishingData, NtosFishingActions>();
  return (
    <NtosWindow theme={data.PC_device_theme} width={340} height={530}>
      <NtosWindow.Content>
        <FishingGame onLose={() => act('lose')} onWin={() => act('win')} />
      </NtosWindow.Content>
    </NtosWindow>
  );
};
