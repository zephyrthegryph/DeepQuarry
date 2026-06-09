// Wiki manual viewer — TGUI.
//
// BYOND's browser used to host external wiki pages inside an iframe;
// TGUI can't (sandbox + no iframe). This window instead shows the
// book's static intro (if any) and a button that opens the wiki page
// in the user's default web browser via `client << link(url)`.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import { HtmlRenderer } from './common/HtmlRenderer';

type Data = {
  title: string;
  intro: string;
  url: string;
};

export const WikiBook = () => {
  const { data, act } = useBackend<Data>();
  const { title, intro, url } = data;
  return (
    <Window width={520} height={520} title={title}>
      <Window.Content scrollable>
        <Section title={title}>
          {intro ? (
            <Box mb={2}>
              <HtmlRenderer html={intro} />
            </Box>
          ) : (
            <Box mb={2}>
              You start skimming through the manual. The full text is hosted on
              the wiki — open it in your web browser to read.
            </Box>
          )}
          {url ? (
            <Box>
              <Button icon="external-link-alt" onClick={() => act('open_wiki')}>
                Open Wiki Page
              </Button>
              <Box mt={1} color="label" italic>
                {url}
              </Box>
            </Box>
          ) : (
            <Box italic color="bad">
              The wiki URL is not configured on this server.
            </Box>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
