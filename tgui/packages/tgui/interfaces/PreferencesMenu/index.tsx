import { useBackend } from 'tgui/backend';

// The Character window is dispatched through the auto-renderer (DQCharacterSetup).
import { DQCharacterSetup } from '../deepquarry/PreferencesMenu/DQCharacterSetup';
import {
  GamePreferencesSelectedPage,
  type PreferencesMenuData,
  Window,
} from './data';
import { GamePreferenceWindow } from './GamePreferenceWindow';

export const PreferencesMenu = () => {
  const { data } = useBackend<PreferencesMenuData>();

  const window = data.window;

  switch (window) {
    case Window.Character:
      return <DQCharacterSetup />;
    case Window.Game:
      return <GamePreferenceWindow />;
    case Window.Keybindings:
      return (
        <GamePreferenceWindow
          startingPage={GamePreferencesSelectedPage.Keybindings}
        />
      );
  }
};
