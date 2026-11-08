import { useAtom, useAtomValue } from 'jotai';
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import {
  activeAt,
  buildPreview,
  LanguagePreview,
  SHORTCUT_MARKERS,
  type TextEdit,
  toggleLanguage,
  toggleMarker,
} from 'tgui/dq';
import { focusMap } from 'tgui/focus';
import { classes } from 'tgui-core/react';
import {
  availableChannelsAtom,
  chatDraftAtom,
  inputFocusRequestAtom,
  languageRulesAtom,
  previewEnabledAtom,
  radioOptionsAtom,
} from './atoms';
import {
  ChatInputModel,
  COMMON_OPTION,
  type InputChannel,
  keyAction,
  MAX_LENGTH,
  nextChannel,
  nextRadioOption,
  parseCommonPrefix,
  parseRadioPrefix,
  previewEntry,
  type RadioOption,
  radioColorName,
  settleChannel,
} from './model';

/** Marks the field for panelFocus.ts, which must not hand focus to the map while it is used. */
export const CHAT_INPUT_ATTRIBUTE = 'data-chat-input';

/**
 * The input row under the chat, where every speech hotkey lands: one channel
 * button on the left (a click or Tab cycles Say, Radio, Me, Whis, Subtle, OOC,
 * LOOC; shift goes back), the radio department in Radio, the text and send.
 * Ctrl+B/I/U and Ctrl+1..9 format and switch language; a live preview shows
 * how a message with languages or formatting will read.
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
  const [value, setValue] = useAtom(chatDraftAtom);
  const [caret, setCaret] = useState(0);
  const pendingSelection = useRef<[number, number] | null>(null);
  const request = useAtomValue(inputFocusRequestAtom);
  const options = useAtomValue(radioOptionsAtom);
  const rules = useAtomValue(languageRulesAtom);
  const available = useAtomValue(availableChannelsAtom);
  const previewEnabled = useAtomValue(previewEnabledAtom);
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

  function setText(text: string) {
    setValue(text);
    input.type(text);
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

  // The speaker's channels changed (lobby, spawn, ghost, a headset): leave one that is gone.
  useEffect(() => {
    const next = settleChannel(input.channel, available);
    if (next !== input.channel) {
      setChannel(next);
    }
  }, [available]);

  useEffect(() => {
    if (!request) {
      return;
    }
    if (request.channel && available.includes(request.channel)) {
      setChannel(request.channel);
    }
    field.current?.focus();
  }, [request]);

  useLayoutEffect(() => {
    const selection = pendingSelection.current;
    if (selection && field.current) {
      field.current.setSelectionRange(selection[0], selection[1]);
      pendingSelection.current = null;
    }
  }, [value]);

  function applyEdit(edit: TextEdit | null) {
    if (!edit || edit.value.length > MAX_LENGTH) {
      return;
    }
    pendingSelection.current = [edit.start, edit.end];
    setCaret(edit.start);
    setText(edit.value);
  }

  /** Ctrl+B/I/U and Ctrl+1..9, read by physical digit so layouts without number-row digits work. */
  function handleShortcut(event: React.KeyboardEvent<HTMLInputElement>) {
    if (!(event.ctrlKey || event.metaKey) || event.shiftKey || event.altKey) {
      return false;
    }
    const { selectionStart, selectionEnd } = event.currentTarget;
    const start = selectionStart ?? value.length;
    const end = selectionEnd ?? start;
    const marker = SHORTCUT_MARKERS[event.key.toLowerCase()];
    if (marker) {
      event.preventDefault();
      event.stopPropagation();
      applyEdit(toggleMarker(value, start, end, marker));
      return true;
    }
    const digit = /^(?:Digit|Numpad)([1-9])$/.exec(event.code);
    if (digit) {
      event.preventDefault();
      event.stopPropagation();
      if (rules) {
        applyEdit(toggleLanguage(value, start, end, Number(digit[1]), rules));
      }
      return true;
    }
    return false;
  }

  function onKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.getModifierState('AltGraph')) {
      return;
    }
    if (handleShortcut(event)) {
      return;
    }
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
        input.step(action === 'next' ? 1 : -1, available);
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

  const active = useMemo(
    () => activeAt(value, caret, rules),
    [value, caret, rules],
  );

  // Parsed on the client from the server's rule data: no round trip per keystroke.
  const preview = useMemo(() => {
    if (!rules || !previewEnabled || !value) {
      return null;
    }
    return buildPreview(previewEntry(channel, radio, value), channel, rules);
  }, [rules, previewEnabled, value, channel, radio]);

  return (
    <div className="ChatInputBox">
      {preview && <LanguagePreview preview={preview} />}
      <div
        className={classes([
          'ChatInput',
          channel === 'Radio'
            ? `ChatInput--radio-${radioColorName(radio.key)}`
            : `ChatInput--${channel}`,
        ])}
      >
        <button
          type="button"
          title="Change channel (Tab)"
          className={classes([
            'ChatInput__channel',
            `ChatInput__channel--${channel}`,
          ])}
          onMouseDown={(event) => event.preventDefault()}
          onClick={(event) => {
            setChannel(
              nextChannel(channel, event.shiftKey ? -1 : 1, available),
            );
            field.current?.focus();
          }}
        >
          {channel}
        </button>
        {channel === 'Radio' && options.length > 0 && (
          <button
            type="button"
            title="Change radio channel"
            className={classes([
              'ChatInput__radio',
              `ChatInput__radio--${radioColorName(radio.key)}`,
            ])}
            onMouseDown={(event) => event.preventDefault()}
            onClick={(event) => {
              setRadio(
                nextRadioOption(radio, options, event.shiftKey ? -1 : 1),
              );
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
          onSelect={(event) =>
            setCaret(event.currentTarget.selectionStart ?? 0)
          }
          onChange={(event) => {
            let text = event.target.value;
            // A typed ":m " switches to that radio channel.
            // Only when the speaker can use the radio now.
            const radioUsable = available.includes('Radio');
            const prefix =
              radioUsable && (channel === 'Say' || channel === 'Radio')
                ? parseRadioPrefix(text, options)
                : null;
            const common = radioUsable
              ? parseCommonPrefix(text, channel)
              : null;
            if (prefix) {
              text = prefix.rest;
              setChannel('Radio');
              setRadio(prefix.option);
            } else if (common !== null) {
              // A leading ";" is the common channel.
              text = common;
              setChannel('Radio');
              setRadio(COMMON_OPTION);
            }
            setCaret(event.target.selectionStart ?? text.length);
            setText(text);
          }}
          onKeyDown={onKeyDown}
        />
        {active && <span className="SpeechIndicator">{active}</span>}
        <button
          type="button"
          className="ChatInput__send"
          onMouseDown={(event) => event.preventDefault()}
          onClick={send}
        >
          Send
        </button>
      </div>
    </div>
  );
}
