import {
  CheckboxInput,
  type FeatureChoiced,
  type FeatureToggle,
} from '../base';
import { FeatureDropdownInput } from '../dropdowns';

export const HotkeyButtons: FeatureToggle = {
  name: 'Hotkey Buttons',
  category: 'UI',
  description:
    'Show the interface buttons that hotkeys can also do (resist, rest, pull and the like).',
  component: CheckboxInput,
};

export const HardsuitActivation: FeatureChoiced = {
  name: 'Hardsuit Activation Click',
  category: 'GAMEPLAY',
  description: 'The click that engages the selected hardsuit module.',
  component: FeatureDropdownInput,
};

export const ShowNutrition: FeatureToggle = {
  name: 'Show Nutrition To Others',
  category: 'GAMEPLAY',
  description:
    'Let other players see your nutrition level when they examine you.',
  component: CheckboxInput,
};

export const MicroPickup: FeatureToggle = {
  name: 'Micro Pick-up',
  category: 'ADULT CONTENT',
  description:
    'Whether your help action (combat mode off) tries to pick up a micro, or to pet, hug or help them. It does not turn off the pick-up mechanics: see the Vore Panel preferences for that.',
  component: CheckboxInput,
};

export const BellyEntranceLogs: FeatureToggle = {
  name: 'Belly Entrance Messages',
  category: 'ADULT CONTENT',
  description: 'Show a chat message when something enters one of your bellies.',
  component: CheckboxInput,
};

export const LiquidbellyVisuals: FeatureToggle = {
  name: 'Liquidbelly Visuals',
  category: 'ADULT CONTENT',
  description:
    'Show the fullscreen liquid effect while you are inside a liquid belly.',
  component: CheckboxInput,
};
