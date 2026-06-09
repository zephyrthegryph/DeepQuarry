// Paper bundle — TGUI.
//
// Page-flips through a stack of papers/photos. Each page shows the
// current sheet's content (paper info as HTML, or a photo placeholder).
// Photo images are not yet wired through TGUI assets, so photo pages
// only show the photo name.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import { HtmlRenderer } from './common/HtmlRenderer';

type Kind = 'paper' | 'photo';

type Data = {
  page: number;
  total_pages: number;
  page_name: string;
  page_kind: Kind;
  page_info: string;
  scribble: string;
};

export const PaperBundle = () => {
  const { data, act } = useBackend<Data>();
  const { page, total_pages, page_name, page_kind, page_info, scribble } = data;
  const isFirst = page === 1;
  const isLast = page === total_pages;

  return (
    <Window width={520} height={620} title={page_name}>
      <Window.Content scrollable>
        <Section>
          <Box mb={1}>
            <Button icon="arrow-left" onClick={() => act('prev_page')}>
              {isFirst ? 'Front' : 'Previous Page'}
            </Button>{' '}
            <Button color="bad" onClick={() => act('remove')}>
              Remove {page_kind}
            </Button>{' '}
            <Button icon="arrow-right" onClick={() => act('next_page')}>
              {isLast ? 'Back' : 'Next Page'}
            </Button>
            <Box inline color="label" ml={2}>
              Page {page} of {total_pages}
            </Box>
          </Box>
        </Section>
        <Section title={page_name}>
          {page_kind === 'paper' ? (
            <HtmlRenderer html={page_info} />
          ) : (
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
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
