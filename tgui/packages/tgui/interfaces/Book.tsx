// Single-page book — TGUI.
//
// Read-only viewer. Content is author-provided HTML written via pen tool.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Section } from 'tgui-core/components';
import { HtmlRenderer } from './common/HtmlRenderer';
import { Label } from 'tgui/components/Label';

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
            <Label italic mb={1}>
              Penned by {author}.
            </Label>
          ) : null}
          <HtmlRenderer html={content} />
        </Section>
      </Window.Content>
    </Window>
  );
};
