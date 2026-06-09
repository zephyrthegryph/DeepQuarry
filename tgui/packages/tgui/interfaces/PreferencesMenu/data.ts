import type { sendAct } from 'tgui/events/act';

// DQEdit — bay_prefs deleted; the legacy constant payload no longer exists.

export enum GamePreferencesSelectedPage {
  Settings,
  Keybindings,
}

export const createSetPreference =
  (act: typeof sendAct, preference: string) => (value: unknown) => {
    act('set_preference', {
      preference,
      value,
    });
  };

export enum Window {
  Character = 0,
  Game = 1,
  Keybindings = 2,
}

export type PreferencesMenuData = {
  character_profiles: (string | null)[];

  character_preferences: {
    game_preferences: Record<string, unknown>;
  };

  active_slot: number;

  window: Window;
};

export type ServerData = {
  // DQEdit — was `legacy: LegacyConstant` (Bay-prefs constants). The new auto-renderer
  // gets its constants per-editor via /datum/preference_editor.build_ui_static_data.
  [key: string]: unknown;
};
