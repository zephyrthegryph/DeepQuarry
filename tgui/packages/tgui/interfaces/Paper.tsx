// Paper — TGUI.
//
// `segments` is an ordered list of {type: "text" | "field", ...}. Text
// segments are pencode-rendered HTML from the in-game pen tool; they go
// through HtmlRenderer (DOMParser-walked into real React) — no
// dangerouslySetInnerHTML. Field segments are positional blanks; in
// write mode each is a Button that opens a tgui_input_text prompt.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import { HtmlRenderer } from './common/HtmlRenderer';

type TextSeg = {
  type: 'text';
  text: string;
};

type FieldSeg = {
  type: 'field';
  id: number;
  text: string;
};

type Segment = TextSeg | FieldSeg;

type Data = {
  view: 'read' | 'write';
  title: string;
  segments: Segment[];
  stamps: string;
  garbled: boolean;
};

export const Paper = () => {
  const { data, act } = useBackend<Data>();
  const { view, title, segments, stamps, garbled } = data;
  const writeMode = view === 'write';

  return (
    <Window width={560} height={620} title={title || 'Paper'}>
      <Window.Content scrollable>
        <Section>
          {segments.map((seg, i) => {
            if (seg.type === 'text') {
              const text = garbled ? scramblePencode(seg.text) : seg.text;
              return (
                <Box inline key={i} style={{ whiteSpace: 'pre-wrap' }}>
                  <HtmlRenderer html={text} act={act} />
                </Box>
              );
            }
            const filled = seg.text && seg.text.trim() !== '';
            if (writeMode) {
              return (
                <Button
                  inline
                  compact
                  key={i}
                  onClick={() => act('write_field', { id: seg.id })}
                >
                  {filled ? seg.text : '_______'}
                </Button>
              );
            }
            return (
              <Box inline key={i} italic color={filled ? undefined : 'label'}>
                {filled ? seg.text : '_______'}
              </Box>
            );
          })}
          {stamps ? (
            <Box mt={2}>
              <HtmlRenderer html={stamps} />
            </Box>
          ) : null}
        </Section>
        {writeMode ? (
          <Section>
            <Button icon="pen" color="good" onClick={() => act('write_end')}>
              Append text at end
            </Button>
          </Section>
        ) : null}
      </Window.Content>
    </Window>
  );
};

// Garble outside of HTML tags only — preserves formatting markup while
// hiding the underlying words, same intent as the legacy stars() helper.
const scramblePencode = (html: string): string => {
  let inTag = false;
  let out = '';
  for (const ch of html) {
    if (ch === '<') inTag = true;
    if (inTag) {
      out += ch;
    } else if (/[a-zA-Z]/.test(ch)) {
      out += '*';
    } else {
      out += ch;
    }
    if (ch === '>') inTag = false;
  }
  return out;
};
