import {
  CheckboxInput,
  type Feature,
  FeatureNumberInput,
  type FeatureNumeric,
  FeatureSliderInput,
  type FeatureToggle,
} from '../base';

export const SOUND_MIDI: FeatureToggle = {
  name: 'Play Admin MIDIs',
  category: 'SOUNDS',
  description: 'Enable hearing admin played sounds.',
  component: CheckboxInput,
};

export const SOUND_LOBBY: FeatureToggle = {
  name: 'Play Lobby Music',
  category: 'SOUNDS',
  description: 'Enable hearing lobby music.',
  component: CheckboxInput,
};

export const sound_instruments: Feature<number> = {
  name: 'Instruments volume',
  category: 'SOUND',
  description: 'Volume of instruments.',
  component: FeatureSliderInput,
};

export const SOUND_MENTORHELP: FeatureToggle = {
  name: 'Mentorhelp Pings',
  category: 'SOUNDS',
  description: 'Enable hearing mentorhelp pings.',
  component: CheckboxInput,
};

export const media_volume: FeatureNumeric = {
  name: 'Jukebox Volume',
  category: 'SOUNDS',
  description: 'The percentage volume of the Jukebox from 0% to 100%.',
  component: FeatureNumberInput,
};
