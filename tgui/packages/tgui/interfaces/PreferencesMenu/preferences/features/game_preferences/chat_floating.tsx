import {
  CheckboxInput,
  type FeatureChoiced,
  type FeatureNumeric,
  FeatureNumberInput,
  type FeatureToggle,
} from '../base';
import { FeatureDropdownInput } from '../dropdowns';

export const chat_floating: FeatureToggle = {
  name: 'Floating chat',
  category: 'UI',
  description:
    'Show chat in its own window you can drag (by its header) and resize, instead of pinned to the right-hand column. Dropping the window at the right edge pins it again.',
  component: CheckboxInput,
};

export const chat_dock_side: FeatureChoiced = {
  name: 'Chat position',
  category: 'UI',
  description:
    'Which end of the right-hand column the pinned chat takes. The stat panel has the rest.',
  component: FeatureDropdownInput,
};

export const chat_share: FeatureNumeric = {
  name: 'Chat size',
  category: 'UI',
  description:
    'How much of the right-hand column the pinned chat takes, in percent (20 to 80). Dragging the divider changes it.',
  component: FeatureNumberInput,
};
