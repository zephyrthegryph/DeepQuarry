// Photo viewer — TGUI.
//
// Renders the photo's icon via icon2html'd <img> HTML (an inline base64
// data: URL) plus the optional scribble on the back.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Section } from 'tgui-core/components';
import { HtmlRenderer } from './common/HtmlRenderer';

type Data = {
  title: string;
  image_html: string;
  scribble: string;
  size: number;
};

export const Photo = () => {
  const { data } = useBackend<Data>();
  const { title, image_html, scribble, size } = data;
  const px = size * 64;
  return (
    <Window
      width={Math.max(px + 32, 320)}
      height={scribble ? 400 : px + 64}
      title={title}
    >
      <Window.Content>
        <Section>
          <Box textAlign="center">
            <HtmlRenderer html={image_html} />
          </Box>
          {scribble ? (
            <Box mt={2}>
              Written on the back:{' '}
              <Box inline italic>
                {scribble}
              </Box>
            </Box>
          ) : null}
        </Section>
      </Window.Content>
    </Window>
  );
};
