import { CheckboxInput, type FeatureToggle } from '../base';

export const chat_floating: FeatureToggle = {
  name: 'Floating chat',
  category: 'UI',
  description:
    'Show chat in its own window you can move and resize, instead of the right-hand panel.',
  component: CheckboxInput,
};
