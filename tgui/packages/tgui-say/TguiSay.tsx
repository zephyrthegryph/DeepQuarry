import './styles/main.scss';

import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { dragStartHandler } from 'tgui/drag';
import { isEscape, KEY } from 'tgui-core/keys';
import { clamp } from 'tgui-core/math';
import { type BooleanLike, classes } from 'tgui-core/react';

import { type Channel, ChannelIterator } from './ChannelIterator';
import { ChatHistory } from './ChatHistory';
import { LineLength, RADIO_PREFIXES, WindowSize } from './constants';
import { resolvePrefix, windowClose, windowOpen, windowSet } from './helpers';
import { LanguagePreview, previewHeight } from './LanguagePreview';
import { buildPreview, type LanguageRules } from './parseLanguages';
import {
  activeAt,
  SHORTCUT_MARKERS,
  type TextEdit,
  toggleLanguage,
  toggleMarker,
} from './shortcuts';
import { byondMessages } from './timers';

type ByondOpen = {
  channel: Channel;
};

type ByondProps = {
  maxLength: number;
  minimumHeight: number;
  minimumWidth: number;
  lightMode: BooleanLike;
  scale: BooleanLike;
  spellcheck: BooleanLike;
  preview: BooleanLike;
};

export function TguiSay() {
  const innerRef = useRef<HTMLTextAreaElement>(null);
  const channelIterator = useRef(new ChannelIterator());
  const chatHistory = useRef(new ChatHistory());
  const messages = useRef(byondMessages);
  const scale = useRef(true);
  const minimumHeight = useRef(WindowSize.Small);
  const minimumWidth = useRef(WindowSize.Width);
  const spellcheck = useRef(true);

  // I initially wanted to make these an object or a reducer, but it's not really worth it.
  // You lose the granulatity and add a lot of boilerplate.
  const [buttonContent, setButtonContent] = useState('');
  const [currentPrefix, setCurrentPrefix] = useState<
    keyof typeof RADIO_PREFIXES | null
  >(null);
  const [maxLength, setMaxLength] = useState(4096);
  const [size, setSize] = useState(WindowSize.Small);
  const [lightMode, setLightMode] = useState(false);
  const [value, setValue] = useState('');
  const [rules, setRules] = useState<LanguageRules | null>(null);
  const [previewEnabled, setPreviewEnabled] = useState(true);

  const position = useRef([window.screenX, window.screenY]);
  const isDragging = useRef(false);
  const appliedExtra = useRef(0);
  const pendingSelection = useRef<[number, number] | null>(null);
  const [caret, setCaret] = useState(0);

  function handleArrowKeys(direction: KEY.PageUp | KEY.PageDown): void {
    const chat = chatHistory.current;
    const iterator = channelIterator.current;

    if (direction === KEY.PageUp) {
      if (chat.isAtLatest() && value) {
        // Save current message to temp history if at the most recent message
        chat.saveTemp(value);
      }
      // Try to get the previous message, fall back to the current value if none
      const prevMessage = chat.getOlderMessage();

      if (prevMessage) {
        setButtonContent(chat.getIndex().toString());
        setValue(prevMessage);
      }
    } else {
      const nextMessage = chat.getNewerMessage() || chat.getTemp() || '';

      const newContent = chat.isAtLatest()
        ? iterator.current()
        : chat.getIndex().toString();

      setButtonContent(newContent);
      setValue(nextMessage);
    }
  }

  function handleBackspaceDelete(): void {
    const chat = chatHistory.current;
    const iterator = channelIterator.current;

    // User is on a chat history message
    if (!chat.isAtLatest()) {
      chat.reset();
      setButtonContent(currentPrefix ?? iterator.current());

      // Empty input, resets the channel
    } else if (currentPrefix && iterator.isSay() && value?.length === 0) {
      setCurrentPrefix(null);
      setButtonContent(iterator.current());
    }
  }

  function handleButtonClick(event: React.MouseEvent<HTMLButtonElement>): void {
    isDragging.current = true;

    setTimeout(() => {
      // So the button doesn't jump around accidentally
      if (isDragging.current) {
        dragStartHandler(event.nativeEvent);
      }
    }, 50);
  }

  // Prevents the button from changing channels if it's dragged
  function handleButtonRelease(): void {
    isDragging.current = false;
    const currentPosition = [window.screenX, window.screenY];

    if (JSON.stringify(position.current) !== JSON.stringify(currentPosition)) {
      position.current = currentPosition;
      return;
    }

    handleIncrementChannel();
  }

  function handleClose(): void {
    innerRef.current?.blur();
    windowClose(minimumWidth.current, minimumHeight.current, scale.current);

    setTimeout(() => {
      chatHistory.current.reset();
      channelIterator.current.reset();
      unloadChat();
    }, 25);
  }

  function handleEnter(): void {
    const iterator = channelIterator.current;
    const prefix = currentPrefix ?? '';

    if (value?.length) {
      if (value.length <= maxLength) {
        chatHistory.current.add(value);
        Byond.sendMessage('entry', {
          channel: iterator.current(),
          entry: iterator.isSay() ? prefix + value : value,
        });
      } else {
        Byond.sendMessage('lenwarn', {
          length: value.length,
          maxlength: maxLength,
        });
        return;
      }
    }
    handleClose();
  }

  function handleForceSay(): void {
    const iterator = channelIterator.current;

    // Only force say if we're on a visible channel and have typed something
    if (!value || iterator.isVisible()) return;

    const prefix = currentPrefix ?? '';
    const grunt = iterator.isSay() ? prefix + value : value;

    messages.current.forceSayMsg(grunt);
    unloadChat();
  }

  function handleIncrementChannel(): void {
    const iterator = channelIterator.current;

    iterator.next();
    setButtonContent(iterator.current());
    setCurrentPrefix(null);
    messages.current.channelIncrementMsg(
      iterator.isVisible(),
      iterator.current(),
    );
  }

  function handleDecrementChannel() {
    const iterator = channelIterator.current;

    iterator.prev();
    setButtonContent(iterator.current());
    setCurrentPrefix(null);
    messages.current.channelIncrementMsg(
      iterator.isVisible(),
      iterator.current(),
    );
  }

  function handleInput(event: React.FormEvent<HTMLTextAreaElement>): void {
    const iterator = channelIterator.current;
    let newValue = event.currentTarget.value;

    const result = resolvePrefix(newValue, currentPrefix, iterator.current());
    const newPrefix = result.prefix;
    // Handles switching prefixes
    if (result.switched && result.channel) {
      newValue = result.value;
      iterator.set(result.channel);
      setCurrentPrefix(newPrefix);
      setButtonContent(newPrefix ? RADIO_PREFIXES[newPrefix] : iterator.current());

      if (newPrefix === ',b ') {
        Byond.sendMessage('thinking', { visible: false });
      }
    }

    // Handles typing indicators
    if (channelIterator.current.isVisible() && newPrefix !== ',b ') {
      messages.current.typingMsg(iterator.current());
    }

    setValue(newValue);
  }

  function applyEdit(edit: TextEdit | null): void {
    if (!edit || edit.value.length > maxLength) return;
    pendingSelection.current = [edit.start, edit.end];
    setValue(edit.value);
    setCaret(edit.start);
  }

  /** Ctrl+B/I/U and Ctrl+1..9, read by physical digit so layouts without number-row digits work. */
  function handleShortcut(
    event: React.KeyboardEvent<HTMLTextAreaElement>,
  ): boolean {
    if (!(event.ctrlKey || event.metaKey) || event.shiftKey || event.altKey) {
      return false;
    }
    const { selectionStart: start, selectionEnd: end } = event.currentTarget;
    const marker = SHORTCUT_MARKERS[event.key.toLowerCase()];
    if (marker) {
      event.preventDefault();
      applyEdit(toggleMarker(value, start, end, marker));
      return true;
    }
    const digit = /^(?:Digit|Numpad)([1-9])$/.exec(event.code);
    if (digit) {
      event.preventDefault();
      if (rules) {
        applyEdit(toggleLanguage(value, start, end, Number(digit[1]), rules));
      }
      return true;
    }
    return false;
  }

  function handleKeyDown(
    event: React.KeyboardEvent<HTMLTextAreaElement>,
  ): void {
    if (event.getModifierState('AltGraph')) return;
    if (handleShortcut(event)) return;

    switch (event.key) {
      case KEY.PageUp:
      case KEY.PageDown:
        event.preventDefault();
        handleArrowKeys(event.key);
        break;

      case KEY.Delete:
      case KEY.Backspace:
        handleBackspaceDelete();
        break;

      case KEY.Enter:
        if (!event.shiftKey) {
          event.preventDefault();
          handleEnter();
        }
        break;

      case KEY.Tab:
        event.preventDefault();
        if (event.shiftKey) {
          handleDecrementChannel();
          break;
        }
        handleIncrementChannel();
        break;

      default:
        if (isEscape(event.key)) {
          handleClose();
        }
    }
  }

  function handleOpen(data: ByondOpen): void {
    setSize(minimumHeight.current);
    channelIterator.current.set(data.channel);

    setCurrentPrefix(null);
    setButtonContent(channelIterator.current.current());
    windowOpen(
      channelIterator.current.current(),
      minimumWidth.current,
      minimumHeight.current,
      scale.current,
    );

    innerRef.current?.focus();
  }

  function handleProps(data: ByondProps): void {
    setMaxLength(data.maxLength);
    const minWidth = clamp(
      data.minimumWidth,
      WindowSize.Width,
      WindowSize.MaxWidth,
    );
    minimumHeight.current = data.minimumHeight;
    minimumWidth.current = minWidth;
    spellcheck.current = !!data.spellcheck;
    setPreviewEnabled(!!data.preview);
    scale.current = !!data.scale;
  }

  function unloadChat(): void {
    setCurrentPrefix(null);
    setButtonContent(channelIterator.current.current());
    setValue('');
  }

  /** Subscribe to Byond messages */
  useEffect(() => {
    Byond.subscribeTo('props', handleProps);
    Byond.subscribeTo('force', handleForceSay);
    Byond.subscribeTo('open', handleOpen);
    Byond.subscribeTo('languageRules', setRules);
  }, []);

  useLayoutEffect(() => {
    const selection = pendingSelection.current;
    if (selection && innerRef.current) {
      innerRef.current.setSelectionRange(selection[0], selection[1]);
      pendingSelection.current = null;
    }
  }, [value]);

  const active = useMemo(
    () => activeAt(value, caret, rules),
    [value, caret, rules],
  );

  // Parsed on the client from the server's rule data: no round trip per keystroke.
  const iteratorChannel = channelIterator.current.current();
  const preview = useMemo(() => {
    if (!rules || !previewEnabled || !value) return null;
    return buildPreview((currentPrefix ?? '') + value, iteratorChannel, rules);
  }, [rules, previewEnabled, value, currentPrefix, iteratorChannel]);
  const extraHeight = preview
    ? previewHeight(preview, minimumWidth.current)
    : 0;

  /** Value has changed, we need to check if the size of the window is ok */
  useEffect(() => {
    const len = value?.length || 0;

    let newSize: WindowSize;
    if (len > LineLength.Medium) {
      newSize = WindowSize.Large;
    } else if (len <= LineLength.Medium && len > LineLength.Small) {
      newSize = WindowSize.Medium;
    } else {
      newSize = WindowSize.Small;
    }
    newSize = clamp(newSize, minimumHeight.current, WindowSize.Max);

    if (size !== newSize || appliedExtra.current !== extraHeight) {
      appliedExtra.current = extraHeight;
      windowSet(minimumWidth.current, newSize + extraHeight, scale.current);
      setSize(newSize);
    }
  }, [value, extraHeight]);

  const theme =
    (lightMode && 'lightMode') ||
    (currentPrefix && RADIO_PREFIXES[currentPrefix]) ||
    channelIterator.current.current();

  return (
    <>
      <div
        className={`window window-${theme} window-${size}`}
        style={{
          zoom: scale.current ? '' : `${100 / window.devicePixelRatio}%`,
          height: extraHeight ? size + extraHeight : undefined,
        }}
        onMouseDown={dragStartHandler}
      />
      <div
        className={classes(['content', lightMode && 'content-lightMode'])}
        style={{
          zoom: scale.current ? '' : `${100 / window.devicePixelRatio}%`,
          bottom: extraHeight ? extraHeight + 2 : undefined,
        }}
      >
        <button
          className={`button button-${theme}`}
          onMouseDown={handleButtonClick}
          onMouseUp={handleButtonRelease}
          type="button"
        >
          {buttonContent}
        </button>
        <textarea
          spellCheck={spellcheck.current}
          autoCorrect="off"
          className={classes([
            'textarea',
            `textarea-${theme}`,
            value.length > LineLength.Large && 'textarea-large',
          ])}
          maxLength={maxLength}
          onInput={handleInput}
          onKeyDown={handleKeyDown}
          onSelect={(event) => setCaret(event.currentTarget.selectionStart)}
          ref={innerRef}
          value={value}
        />
        {active && (
          <span
            className={classes([
              'indicator',
              lightMode && 'indicator-lightMode',
            ])}
          >
            {active}
          </span>
        )}
        <button
          key="escape"
          className={`button button-${theme}`}
          onClick={handleClose}
          type="submit"
        >
          X
        </button>
      </div>
      {preview && (
        <LanguagePreview
          preview={preview}
          height={extraHeight}
          lightMode={lightMode}
          zoom={scale.current ? '' : `${100 / window.devicePixelRatio}%`}
        />
      )}
    </>
  );
}
