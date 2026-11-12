import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  RestrictedInput,
  Section,
  Stack,
} from 'tgui-core/components';
import { isEscape, KEY } from 'tgui-core/keys';

import { InputButtons } from './common/InputButtons';
import { Loader } from './common/Loader';
import type {
  NumberInputModalActions,
  NumberInputModalData,
} from './generated/NumberInputModal';

type Data = NumberInputModalData;

export function NumberInputModal(props) {
  const { act, data } = useBackend<Data, NumberInputModalActions>();
  const { large_buttons, round_value, timeout, title } = data;
  const message = data.message ?? '';
  // A bound or starting value the server leaves null reads as the default range and its minimum.
  const max_value = data.max_value ?? 10000;
  const min_value = data.min_value ?? 0;
  const init_value = data.init_value ?? min_value;

  const [value, setValue] = useState(init_value);
  const [isValid, setIsValid] = useState(true);

  // Dynamically changes the window height based on the message.
  const windowHeight =
    140 +
    (message.length > 30 ? Math.ceil(message.length / 3) : 0) +
    (message.length && large_buttons ? 5 : 0);

  function handleKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    if (event.key === KEY.Enter && isValid) {
      act('submit', { entry: value });
    }
    if (isEscape(event.key)) {
      act('cancel');
    }
  }

  return (
    <Window
      fitContent
      title={title}
      width={270}
      height={windowHeight}
    >
      {!!timeout && <Loader value={timeout} />}
      <Window.Content onKeyDown={handleKeyDown}>
        <Section fill>
          <Stack fill vertical>
            <Stack.Item grow>
              <Box color="label">{message}</Box>
            </Stack.Item>
            <Stack.Item>
              <Stack fill>
                <Stack.Item>
                  <Button
                    disabled={value === min_value || min_value === -Infinity}
                    icon={
                      min_value === -Infinity ? 'infinity' : 'angle-double-left'
                    }
                    onClick={() => setValue(min_value ?? 0)}
                    tooltip={min_value ? `Min (${min_value})` : 'Min'}
                  />
                </Stack.Item>

                <Stack.Item>
                  <Button
                    icon="angle-down"
                    disabled={value <= min_value}
                    onClick={() => setValue((value) => value - 1)}
                  />
                </Stack.Item>

                <Stack.Item grow>
                  <RestrictedInput
                    autoFocus
                    autoSelect
                    fluid
                    allowFloats={!round_value}
                    minValue={min_value}
                    maxValue={max_value}
                    onChange={setValue}
                    onValidationChange={setIsValid}
                    value={value}
                  />
                </Stack.Item>

                <Stack.Item>
                  <Button
                    icon="angle-up"
                    disabled={value >= max_value}
                    onClick={() => setValue((value) => value + 1)}
                  />
                </Stack.Item>

                <Stack.Item>
                  <Button
                    disabled={value === max_value || max_value === Infinity}
                    icon={
                      max_value === Infinity ? 'infinity' : 'angle-double-right'
                    }
                    onClick={() => setValue(max_value ?? 10000)}
                    tooltip={max_value ? `Max (${max_value})` : 'Max'}
                  />
                </Stack.Item>
                <Stack.Item>
                  <Button
                    disabled={value === init_value}
                    icon="redo"
                    onClick={() => setValue(init_value ?? 0)}
                    tooltip={init_value ? `Reset (${init_value})` : 'Reset'}
                  />
                </Stack.Item>
              </Stack>
            </Stack.Item>
            <Stack.Item>
              <InputButtons input={value} disabled={!isValid} />
            </Stack.Item>
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
}
