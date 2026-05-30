// Admin paper — TGUI.
//
// Same segment-based body as Paper.tsx plus optional header/footer HTML
// and an admin action bar (send fax, pen mode toggle, header/footer
// toggles, clear, cancel).

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
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
  title: string;
  segments: Segment[];
  stamps: string;
  header_html: string;
  footer_html: string;
  header_on: BooleanLike;
  footer_on: BooleanLike;
  is_crayon: BooleanLike;
};

export const AdminPaper = () => {
  const { data, act } = useBackend<Data>();
  const {
    title,
    segments,
    stamps,
    header_html,
    footer_html,
    header_on,
    footer_on,
    is_crayon,
  } = data;

  return (
    <Window width={620} height={680} title={title}>
      <Window.Content scrollable>
        <Section
          title="Fax"
          buttons={
            <>
              <Button
                icon="paper-plane"
                color="good"
                onClick={() => act('confirm')}
              >
                Send Fax
              </Button>{' '}
              <Button onClick={() => act('penmode')}>
                Pen Mode: {is_crayon ? 'Crayon' : 'Pen'}
              </Button>{' '}
              <Button color="bad" onClick={() => act('cancel')}>
                Cancel
              </Button>
            </>
          }
        >
          <Button selected={!!header_on} onClick={() => act('toggleheader')}>
            Header: {header_on ? 'On' : 'Off'}
          </Button>{' '}
          <Button selected={!!footer_on} onClick={() => act('togglefooter')}>
            Footer: {footer_on ? 'On' : 'Off'}
          </Button>{' '}
          <Button color="bad" onClick={() => act('clear')}>
            Clear Page
          </Button>
        </Section>

        <Section>
          {header_on && header_html ? (
            <HtmlRenderer html={header_html} />
          ) : null}
          <Box mt={1}>
            {segments.map((seg, i) => {
              if (seg.type === 'text') {
                return (
                  <Box inline key={i} style={{ whiteSpace: 'pre-wrap' }}>
                    <HtmlRenderer html={seg.text} />
                  </Box>
                );
              }
              const filled = seg.text && seg.text.trim() !== '';
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
            })}
          </Box>
          {stamps ? (
            <Box mt={2}>
              <HtmlRenderer html={stamps} />
            </Box>
          ) : null}
          {footer_on && footer_html ? (
            <Box mt={2}>
              <HtmlRenderer html={footer_html} />
            </Box>
          ) : null}
        </Section>

        <Section>
          <Button icon="pen" color="good" onClick={() => act('write_end')}>
            Append text at end
          </Button>
        </Section>
      </Window.Content>
    </Window>
  );
};
