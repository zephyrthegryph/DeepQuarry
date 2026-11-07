import { useAtomValue } from 'jotai';
import { useEffect, useRef, useState } from 'react';
import { focusMap } from 'tgui/focus';
import { classes } from 'tgui-core/react';
import { inputFocusRequestAtom, radioOptionsAtom } from './atoms';
import {
  ChatInputModel,
  type InputChannel,
  keyAction,
  MAX_LENGTH,
  nextChannel,
  nextRadioOption,
  parseRadioPrefix,
  type RadioOption,
} from './model';

/** Marks the field for panelFocus.ts, which must not hand focus to the map while it is used. */
export const CHAT_INPUT_ATTRIBUTE = 'data-chat-input';

/**
 * The persistent input row under the chat, like the say popup: one channel
 * button on the left (a click or Tab cycles Say, Radio, Me, OOC, LOOC; shift
 * goes back), the text and send.
 */
export function ChatInput() {
  const model = useRef<ChatInputModel | null>(null);
  if (!model.current) {
    model.current = new ChatInputModel((type, payload) =>
      Byond.sendMessage(type, payload),
    );
  }
  const input = model.current;
  const field = useRef<HTMLInputElement>(null);
  const [channel, setChannelState] = useState<InputChannel>('Say');
  const [value, setValue] = useState('');
  const request = useAtomValue(inputFocusRequestAtom);
  const options = useAtomValue(radioOptionsAtom);
  const [radio, setRadioState] = useState<RadioOption>(input.radio);

  useEffect(() => {
    input.syncRadio(options);
    setRadioState(input.radio);
  }, [input, options]);

  function setRadio(next: RadioOption) {
    input.setRadio(next);
    setRadioState(next);
  }

  function setChannel(next: InputChannel) {
    input.setChannel(next);
    setChannelState(next);
  }

  function returnToMap() {
    field.current?.blur();
    input.close();
    focusMap();
  }

  function send() {
    if (input.submit()) {
      setValue('');
      returnToMap();
    }
  }

  useEffect(() => {
    if (!request) {
      return;
    }
    if (request.channel) {
      setChannel(request.channel);
    }
    field.current?.focus();
  }, [request]);

  function onKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    const action = keyAction(event.key, event.shiftKey);
    if (!action) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    switch (action) {
      case 'send':
        send();
        break;
      case 'escape':
        returnToMap();
        break;
      case 'next':
      case 'prev':
        input.step(action === 'next' ? 1 : -1);
        setChannelState(input.channel);
        break;
      case 'older':
      case 'newer': {
        const text = input.recall(action);
        if (text !== null) {
          setValue(text);
        }
        break;
      }
    }
  }

  return (
    <div className="ChatInput">
      <button
        type="button"
        title="Change channel (Tab)"
        className={classes([
          'ChatInput__channel',
          `ChatInput__channel--${channel}`,
        ])}
        onMouseDown={(event) => event.preventDefault()}
        onClick={(event) => {
          setChannel(nextChannel(channel, event.shiftKey ? -1 : 1));
          field.current?.focus();
        }}
      >
        {channel}
      </button>
      {channel === 'Radio' && options.length > 0 && (
        <button
          type="button"
          title="Change radio channel"
          className="ChatInput__radio"
          onMouseDown={(event) => event.preventDefault()}
          onClick={(event) => {
            setRadio(nextRadioOption(radio, options, event.shiftKey ? -1 : 1));
            field.current?.focus();
          }}
        >
          {radio.label}
        </button>
      )}
      <input
        {...{ [CHAT_INPUT_ATTRIBUTE]: true }}
        ref={field}
        className="ChatInput__field"
        type="text"
        autoComplete="off"
        spellCheck
        maxLength={MAX_LENGTH}
        placeholder={`${channel}...`}
        value={value}
        onFocus={() => input.open(channel)}
        onBlur={() => input.close()}
        onChange={(event) => {
          let text = event.target.value;
          // A typed ":m " switches to that radio channel, like the say popup.
          const prefix =
            channel === 'Say' || channel === 'Radio'
              ? parseRadioPrefix(text, options)
              : null;
          if (prefix) {
            text = prefix.rest;
            setChannel('Radio');
            setRadio(prefix.option);
          }
          setValue(text);
          input.type(text);
        }}
        onKeyDown={onKeyDown}
      />
      <button
        type="button"
        className="ChatInput__send"
        onMouseDown={(event) => event.preventDefault()}
        onClick={send}
      >
        Send
      </button>
    </div>
  );
}
