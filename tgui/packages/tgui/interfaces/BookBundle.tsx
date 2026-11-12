// Multi-page book bundle — TGUI.
//
// Page-flips through bundled pages, which can be paper, photo, or plain
// HTML strings. Photo images are not yet wired through TGUI assets — photo
// pages show name + scribble only.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import { HtmlRenderer } from './common/HtmlRenderer';
import type { BookBundleActions, BookBundleData } from './generated/BookBundle';
import { Label } from 'tgui/components/Label';

export const BookBundle = () => {
  const { data, act } = useBackend<BookBundleData, BookBundleActions>();
  const { page, total_pages, page_name, page_kind, page_info, scribble } = data;
  const isFirst = page === 1;
  const isLast = page === total_pages;

  return (
    <Window width={520} height={620} title={page_name}>
      <Window.Content scrollable>
        <Section>
          <Button icon="arrow-left" onClick={() => act('prev_page')}>
            {isFirst ? 'Front' : 'Previous Page'}
          </Button>{' '}
          <Label inline mx={2}>
            Page {page} of {total_pages}
          </Label>
          <Button icon="arrow-right" onClick={() => act('next_page')}>
            {isLast ? 'Back' : 'Next Page'}
          </Button>
        </Section>
        <Section title={page_kind === 'photo' ? page_name : ''}>
          {page_kind === 'photo' ? (
            <>
              <Label italic mb={1}>
                Photo: {page_name}
              </Label>
              {scribble ? (
                <Box>
                  Written on the back:{' '}
                  <Box inline italic>
                    {scribble}
                  </Box>
                </Box>
              ) : null}
            </>
          ) : (
            <HtmlRenderer html={page_info} />
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
