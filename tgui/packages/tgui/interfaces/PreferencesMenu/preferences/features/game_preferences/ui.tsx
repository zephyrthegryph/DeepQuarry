import { CheckboxInput, type FeatureToggle } from '../base';

export const screentips_optin: FeatureToggle = {
  name: 'Screentips',
  category: 'UI',
  description:
    'Show what clicking and alt-clicking would do to the thing under your mouse.',
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
  description: 'Enables spellchecking on TGUI text areas and TGUI Say.',
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
