import { useBackend } from 'tgui/backend';

// DQEdit — dispatch the Character window through the new auto-renderer instead of the
// legacy Bay-prefs window. The legacy CharacterPreferenceWindow remains in the file for
// reference until the demolition pass removes it.
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
