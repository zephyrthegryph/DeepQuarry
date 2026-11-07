import { CheckboxInput, type FeatureToggle } from '../base';

export const WHISUBTLE_VIS: FeatureToggle = {
  name: 'Allow ghosts to see whispers/subtles',
  category: 'GHOST',
  description: 'Enables ghosts to see your whispers and subtle emotes.',
  component: CheckboxInput,
};


export const CHAT_GHOSTEARS: FeatureToggle = {
  name: 'Ghost Ears',
  category: 'GHOST',
  description: 'When enabled, hear all speech; otherwise, only hear nearby.',
  component: CheckboxInput,
};


