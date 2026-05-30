// Exonet Message Log — structured TGUI.
// Each line is server-rendered HTML (bold "To X:" header followed by message body).

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Section } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';
import { HtmlRenderer } from './common/HtmlRenderer';

type Data = {
  lines: string[];
};

export const ExonetLog = () => {
  const { data } = useBackend<Data>();
  const { lines } = data;
  return (
    <Window width={520} height={520} title="Exonet Message Log">
      <Window.Content scrollable>
        <Section title="Exonet Message Log">
          {lines.length === 0 ? (
            <EmptyState>No messages.</EmptyState>
          ) : (
            lines.map((line, i) => (
              <Box key={i} mb={1}>
                <HtmlRenderer html={line} />
              </Box>
            ))
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
