import { CheckboxInput, type FeatureToggle } from '../base';

export const MicroPickup: FeatureToggle = {
  name: 'Micro Pick-up',
  category: 'ADULT CONTENT',
  description:
    'Whether your help action (combat mode off) tries to pick up a micro, or to pet, hug or help them. It does not turn off the pick-up mechanics: see the Vore Panel preferences for that.',
  component: CheckboxInput,
};
