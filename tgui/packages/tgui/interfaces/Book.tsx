// Single-page book — TGUI.
//
// Read-only viewer. Content is author-provided HTML written via pen tool.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Section } from 'tgui-core/components';
import { HtmlRenderer } from './common/HtmlRenderer';

type Data = {
  title: string;
  author: string;
  content: string;
};

export const Book = () => {
  const { data } = useBackend<Data>();
  const { title, author, content } = data;

  return (
    <Window width={520} height={620} title={title || 'Book'}>
      <Window.Content scrollable>
        <Section>
          {author ? (
            <Box italic color="label" mb={1}>
              Penned by {author}.
            </Box>
          ) : null}
          <HtmlRenderer html={content} />
        </Section>
      </Window.Content>
    </Window>
  );
};
