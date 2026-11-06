import { CheckboxInput, type FeatureToggle } from '../base';

export const chat_inline_input: FeatureToggle = {
  name: 'Type in the chat window',
  category: 'UI',
  description:
    'While the chat floats, the say, emote and OOC hotkeys focus the input row in the chat window instead of opening the popup.',
  component: CheckboxInput,
};
