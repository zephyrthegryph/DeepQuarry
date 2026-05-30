// Multi-page book bundle — TGUI.
//
// Page-flips through bundled pages, which can be paper, photo, or plain
// HTML strings. Photo images are not yet wired through TGUI assets — photo
// pages show name + scribble only.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import { HtmlRenderer } from './common/HtmlRenderer';

type Kind = 'paper' | 'photo' | 'text';

type Data = {
  page: number;
  total_pages: number;
  page_name: string;
  page_kind: Kind;
  page_info: string;
  scribble: string;
};

export const BookBundle = () => {
  const { data, act } = useBackend<Data>();
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
          <Box inline color="label" mx={2}>
            Page {page} of {total_pages}
          </Box>
          <Button icon="arrow-right" onClick={() => act('next_page')}>
            {isLast ? 'Back' : 'Next Page'}
          </Button>
        </Section>
        <Section title={page_kind === 'photo' ? page_name : ''}>
          {page_kind === 'photo' ? (
            <>
              <Box italic color="label" mb={1}>
                Photo: {page_name}
              </Box>
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
