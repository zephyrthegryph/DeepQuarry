// DQAdd — A text area that shows the chat's emphasis as you type, in the box itself: the text is drawn formatted behind a
// transparent textarea (same monospace font, so bold never moves a character), and Ctrl+B/I/U toggle the chat's markers
// with the say box's own edit (tgui/dq toggleMarker). The markers come from the server (GLOB.speech_toppings).

import { useLayoutEffect, useRef, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { FormattedBackdrop, SHORTCUT_MARKERS, toggleMarker } from 'tgui/dq';

/// The chat's markers; the say box's defaults until the server's arrive.
export const DEFAULT_MARKERS: Record<string, string> = {
  '|': 'i',
  '+': 'b',
  _: 'u',
};

const BOX_STYLE: React.CSSProperties = {
  boxSizing: 'border-box',
  width: '100%',
  height: '100%',
  margin: 0,
  padding: '0.4em 0.5em',
  fontFamily: 'Consolas, "Lucida Console", monospace',
  fontSize: '1em',
  lineHeight: '1.35',
  whiteSpace: 'pre-wrap',
  overflowWrap: 'anywhere',
  border: '1px solid rgba(255,255,255,0.2)',
  borderRadius: '0.2em',
};

export const FormattingTextArea = ({
  value,
  onChange,
  onBlur,
  height = '10em',
  maxLength,
}: {
  value: string;
  onChange: (value: string) => void;
  onBlur?: () => void;
  height?: string;
  maxLength?: number;
}) => {
  const { data } = useBackend<{ dq_text_markers?: Record<string, string> }>();
  const markers = data.dq_text_markers ?? DEFAULT_MARKERS;
  const area = useRef<HTMLTextAreaElement>(null);
  const backdrop = useRef<HTMLDivElement>(null);
  const [caret, setCaret] = useState<[number, number] | null>(null);
  useLayoutEffect(() => {
    if (caret && area.current) {
      area.current.setSelectionRange(caret[0], caret[1]);
      setCaret(null);
    }
  }, [caret]);
  const syncScroll = () => {
    if (backdrop.current && area.current) {
      backdrop.current.scrollTop = area.current.scrollTop;
    }
  };
  const onKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (!(event.ctrlKey || event.metaKey) || event.shiftKey || event.altKey) {
      return;
    }
    const marker = SHORTCUT_MARKERS[event.key.toLowerCase()];
    if (!marker) return;
    event.preventDefault();
    const { selectionStart, selectionEnd } = event.currentTarget;
    const edit = toggleMarker(value, selectionStart, selectionEnd, marker);
    onChange(edit.value);
    setCaret([edit.start, edit.end]);
  };
  return (
    <div style={{ position: 'relative', height }}>
      <div
        ref={backdrop}
        aria-hidden
        className="dq-formatting-backdrop"
        style={{
          ...BOX_STYLE,
          position: 'absolute',
          inset: 0,
          overflow: 'hidden',
          background: 'rgba(0,0,0,0.25)',
          color: 'inherit',
        }}
      >
        <FormattedBackdrop text={value} markers={markers} />
        {/* a trailing line break would collapse without this */}
        {'\u200b'}
      </div>
      <textarea
        ref={area}
        className="dq-formatting-input"
        value={value}
        maxLength={maxLength}
        spellCheck={false}
        onChange={(e) => onChange(e.target.value)}
        onBlur={onBlur}
        onKeyDown={onKeyDown}
        onScroll={syncScroll}
        style={{
          ...BOX_STYLE,
          position: 'relative',
          resize: 'none',
          overflow: 'auto',
          background: 'transparent',
          color: 'transparent',
          caretColor: '#fff',
        }}
      />
    </div>
  );
};
