import {
  CheckboxInput,
  type FeatureChoiced,
  type FeatureToggle,
} from '../base';
import { FeatureDropdownInput } from '../dropdowns';


export const SHOW_TYPING: FeatureToggle = {
  name: 'Typing Indicator',
  category: 'CHAT',
  description: 'Show a typing indicator when you are typing ingame.',
  component: CheckboxInput,
};


export const CHAT_OOC: FeatureToggle = {
  name: 'OOC Chat',
  category: 'CHAT',
  description: 'Enables OOC chat.',
  component: CheckboxInput,
};

export const CHAT_LOOC: FeatureToggle = {
  name: 'LOOC Chat',
  category: 'CHAT',
  description: 'Enables L(ocal)OOC chat.',
  component: CheckboxInput,
};

export const CHAT_DEAD: FeatureToggle = {
  name: 'Dead Chat',
  category: 'CHAT',
  description: 'Enables observer/dead/ghost chat.',
  component: CheckboxInput,
};

export const CHAT_MENTION: FeatureToggle = {
  name: 'Emphasize Name Mention',
  category: 'CHAT',
  description:
    'Makes messages containing your name or nickname appear larger to get your attention.',
  component: CheckboxInput,
};




export const EXAMINE_MODE: FeatureChoiced = {
  name: 'Examine Mode',
  category: 'CHAT',
  description:
    'Choose how you want to examine items. "Verbose" will include all information found in the examine panel as foldable groups, "Switch To Panel" will switch you to the examine panel upon examining, and "Slim" will do neither. ',
  component: FeatureDropdownInput,
};

