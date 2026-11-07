import { CheckboxInput, type FeatureToggle } from '../base';

export const AMBIENT_OCCLUSION_PREF: FeatureToggle = {
  name: 'Enable ambient occlusion',
  category: 'GAMEPLAY',
  description: 'Enable ambient occlusion, light shadows around characters.',
  component: CheckboxInput,
};

export const BrowserDevTools: FeatureToggle = {
  name: 'Browser Dev Tools',
  category: 'UI',
  description:
    'When enabled, you can right click -> inspect to open Microsoft Edge dev tools. BYOND 516+ Only.',
  component: CheckboxInput,
};

export const AUTOTRANSCORE: FeatureToggle = {
  name: 'Automatically Notify Transcore on Death',
  category: 'GAMEPLAY',
  description: 'Do you want medbay to know you died automatically?',
  component: CheckboxInput,
};
