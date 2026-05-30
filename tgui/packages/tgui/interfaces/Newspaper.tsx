// In-game newspaper — TGUI.
//
// Multi-page reader. The DM side ships all channels + wanted + scribble
// in one payload; React handles page-flip navigation. Photo embedding
// (the legacy browse_rsc flow) is not yet wired through TGUI assets, so
// photos are omitted in this view.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Message = {
  title: string;
  body: string;
  author: string;
  message_type: string;
};

type Channel = {
  name: string;
  author: string;
  censored: BooleanLike;
  messages: Message[];
};

type Wanted = {
  author: string;
  body: string;
} | null;

type Data = {
  company_name: string;
  channels: Channel[];
  wanted: Wanted;
  scribble: string;
  scribble_page: number;
  curr_page: number;
};

export const Newspaper = () => {
  const { data, act } = useBackend<Data>();
  const { company_name, channels, wanted, scribble, scribble_page, curr_page } =
    data;

  const pages = channels.length;
  const totalPages = 1 + pages + 1; // cover + channels + wanted
  const showScribble = scribble_page === curr_page && scribble;

  const renderCover = () => (
    <Section>
      <Box textAlign="center" fontSize="1.6em" bold>
        The Griffon
      </Box>
      <Box textAlign="center" italic color="label" mb={2}>
        {company_name}-standard newspaper, for use on {company_name} Space
        Facilities
      </Box>
      <Box bold mb={1}>
        Contents:
      </Box>
      {channels.length === 0 && !wanted ? (
        <EmptyState>
          Other than the title, the rest of the newspaper is unprinted…
        </EmptyState>
      ) : (
        <Stack vertical>
          {wanted ? (
            <Stack.Item>
              <Box bold color="bad">
                ** Important Security Announcement ** —{' '}
                <Box inline color="label">
                  page {pages + 2}
                </Box>
              </Box>
            </Stack.Item>
          ) : null}
          {channels.map((c, i) => (
            <Stack.Item key={c.name}>
              <Box bold>
                {c.name}{' '}
                <Box inline color="label">
                  page {i + 2}
                </Box>
              </Box>
            </Stack.Item>
          ))}
        </Stack>
      )}
    </Section>
  );

  const renderChannel = () => {
    const idx = curr_page - 1;
    const c = channels[idx];
    if (!c) return null;
    return (
      <Section title={c.name}>
        <Box color="label" italic mb={1}>
          created by {c.author}
        </Box>
        {c.censored ? (
          <Box color="bad" italic>
            This channel was deemed dangerous to the general welfare of the
            station and marked with a D-Notice. Its contents were not
            transferred to the newspaper at the time of printing.
          </Box>
        ) : c.messages.length === 0 ? (
          <EmptyState>No Feed stories stem from this channel…</EmptyState>
        ) : (
          <Stack vertical>
            {c.messages.map((m, i) => (
              <Stack.Item key={i}>
                <Box bold>{m.title}</Box>
                <Box>{m.body}</Box>
                <Box color="label" italic fontSize="0.85em" mb={1}>
                  [{m.message_type} by {m.author}]
                </Box>
              </Stack.Item>
            ))}
          </Stack>
        )}
      </Section>
    );
  };

  const renderWanted = () =>
    wanted ? (
      <Section title="Wanted Issue">
        <Box bold mb={1}>
          Criminal name: <Box inline>{wanted.author}</Box>
        </Box>
        <Box bold mb={1}>
          Description:
        </Box>
        <Box mb={1}>{wanted.body}</Box>
      </Section>
    ) : (
      <Section>
        <EmptyState>
          Apart from some uninteresting Classified ads, there's nothing on this
          page…
        </EmptyState>
      </Section>
    );

  return (
    <Window width={520} height={620}>
      <Window.Content scrollable>
        {curr_page === 0 ? renderCover() : null}
        {curr_page >= 1 && curr_page <= pages ? renderChannel() : null}
        {curr_page === pages + 1 ? renderWanted() : null}
        {showScribble ? (
          <Box italic color="label" mt={1}>
            There is a small scribble near the end of this page… It reads: "
            {scribble}"
          </Box>
        ) : null}
        <Box mt={2}>
          {curr_page > 0 ? (
            <Button icon="arrow-left" onClick={() => act('prev_page')}>
              Previous Page
            </Button>
          ) : null}{' '}
          <Box inline color="label" mx={2}>
            Page {curr_page + 1} of {totalPages}
          </Box>
          {curr_page < totalPages - 1 ? (
            <Button icon="arrow-right" onClick={() => act('next_page')}>
              Next Page
            </Button>
          ) : null}
        </Box>
      </Window.Content>
    </Window>
  );
};
