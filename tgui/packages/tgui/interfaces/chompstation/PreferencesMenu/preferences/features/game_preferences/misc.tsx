import {
  CheckboxInput,
  type FeatureToggle,
} from 'tgui/interfaces/PreferencesMenu/preferences/features/base';


export const AUTOTRANSCORE: FeatureToggle = {
  name: 'Automatic transcore notification',
  category: 'GAMEPLAY',
  description: 'Enable automatic transcore notification.',
  component: CheckboxInput,
};
