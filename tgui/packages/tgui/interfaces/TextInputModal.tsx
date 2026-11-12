import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Section, Stack, TextArea } from 'tgui-core/components';
import { isEscape, KEY } from 'tgui-core/keys';
import { InputButtons } from './common/InputButtons';
import { Loader } from './common/Loader';
import type {
  TextInputModalActions,
  TextInputModalData,
} from './generated/TextInputModal';
import { Label } from 'tgui/components/Label';

type TextInputData = TextInputModalData;

export const sanitizeMultiline = (toSanitize: string) => {
  return toSanitize.replace(/(\n|\r\n){3,}/, '\n\n');
};

export const removeAllSkiplines = (toSanitize: string) => {
  return toSanitize.replace(/[\r\n]+/, '');
};

export const TextInputModal = (props) => {
  const { act, data } = useBackend<TextInputData, TextInputModalActions>();
  const { large_buttons, max_length, multiline, timeout, title, spellcheck } =
    data;
  const message = data.message ?? '';
  const placeholder = data.placeholder ?? '';

  const [input, setInput] = useState(placeholder || '');

  function onType(value: string) {
    if (value === input) {
      return;
    }
    const sanitizedInput = multiline
      ? sanitizeMultiline(value)
      : removeAllSkiplines(value);
    setInput(sanitizedInput);
  }

  const visualMultiline = multiline || input.length >= 30;
  // Dynamically changes the window height based on the message.
  const windowHeight =
    135 +
    (message.length > 30 ? Math.ceil(message.length / 2.7) : 0) +
    (visualMultiline ? 75 : 0) +
    (message.length && large_buttons ? 5 : 0);

  function handleKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    if (event.key === KEY.Enter && (!visualMultiline || !event.shiftKey)) {
      act('submit', { entry: input });
    }
    if (isEscape(event.key)) {
      act('cancel');
    }
  }

  // This is the length of the input in terms of unicode code points.
  // Should be equivalent to what length_char would output for the same string in BYOND.
  const char_length = [...input].length;

  return (
    <Window fitContent title={title} width={325} height={windowHeight}>
      {!!timeout && <Loader value={timeout} />}
      <Window.Content onKeyDown={handleKeyDown}>
        <Section fill>
          <Stack fill vertical>
            <Stack.Item>
              <Label>{message}</Label>
            </Stack.Item>
            <Stack.Item grow>
              <TextArea
                autoFocus
                autoSelect
                fluid
                spellcheck={!!spellcheck}
                userMarkup={{ u: '_', i: '|', b: '+' }}
                height={multiline || input.length >= 30 ? '100%' : '1.8rem'}
                maxLength={max_length ?? undefined}
                onEscape={() => act('cancel')}
                onChange={onType}
                placeholder="Type something..."
                value={input}
              />
            </Stack.Item>
            <Stack.Item>
              <InputButtons
                input={input}
                message={`${char_length}/${max_length || '∞'}`}
              />
            </Stack.Item>
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};
