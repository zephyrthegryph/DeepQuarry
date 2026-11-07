import {
  CheckboxInput,
  type FeatureToggle,
} from '../base';


export const VCHAT_ENABLE: FeatureToggle = {
  name: 'Enable TGChat',
  category: 'UI',
  description: 'Enable the TGChat chat panel.',
  component: CheckboxInput,
};

export const screentips_optin: FeatureToggle = {
  name: 'Screentips',
  category: 'UI',
  description:
    'Show what clicking and alt-clicking would do to the thing under your mouse.',
  component: CheckboxInput,
};

export const tgui_fancy: FeatureToggle = {
  name: 'TGUI: Fancy Mode',
  category: 'UI',
  description: 'When enabled, hide the title bar and fully style tgui windows.',
  component: CheckboxInput,
};

export const tgui_lock: FeatureToggle = {
  name: 'TGUI: Window Lock',
  category: 'UI',
  description:
    'When enabled, forces windows to spawn on the primary monitor - otherwise, any monitor.',
  component: CheckboxInput,
};

export const tgui_input_mode: FeatureToggle = {
  name: 'TGUI: Input Framework',
  category: 'UI',
  description: 'Enable TGUI based input for most input dialogs.',
  component: CheckboxInput,
};

export const tgui_large_buttons: FeatureToggle = {
  name: 'TGUI: Large Buttons',
  category: 'UI',
  description: 'Use large buttons in TGUI Input windows.',
  component: CheckboxInput,
};

export const tgui_swapped_buttons: FeatureToggle = {
  name: 'TGUI: Swapped Buttons',
  category: 'UI',
  description: 'Swap the position of OK and Cancel buttons.',
  component: CheckboxInput,
};

export const ui_scale: FeatureToggle = {
  name: 'Toggle UI scaling',
  category: 'UI',
  description: 'If UIs should scale up to match your monitor scaling.',
  component: CheckboxInput,
};

export const TGUI_ENABLE_SPELLCHECK: FeatureToggle = {
  name: 'TGUI: Spellcheck',
  category: 'UI',
  description: 'Enables spellchecking on TGUI text areas.',
  component: CheckboxInput,
};

export const TGUI_SAY_PREVIEW: FeatureToggle = {
  name: 'Chat input: Language and formatting preview',
  category: 'UI',
  description:
    'Shows how a message with languages or formatting will read as you type it.',
  component: CheckboxInput,
};

export const windowflashing: FeatureToggle = {
  name: 'Enable window flashing',
  category: 'UI',
  description: `
    When toggled, some important events will make your game icon flash on your
    task tray.
  `,
  component: CheckboxInput,
};
