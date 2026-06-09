// Latest News (station newspaper) — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';
import { HtmlRenderer } from './common/HtmlRenderer';

type Data = {
  channel_name: string;
  page: number;
  total: number;
  has_messages: BooleanLike;
  title?: string;
  author?: string;
  body?: string;
};

export const LatestNews = () => {
  const { data, act } = useBackend<Data>();
  const { channel_name, page, total, has_messages, title, author, body } = data;
  return (
    <Window width={560} height={620} title="Latest News">
      <Window.Content scrollable>
        <Section title={channel_name}>
          {!has_messages ? (
            <EmptyState>
              No current available news, it may still be loading!
            </EmptyState>
          ) : (
            <>
              <Box bold mb={1}>
                {title}
              </Box>
              <Box mb={1}>
                <HtmlRenderer html={body ?? ''} />
              </Box>
              <Box italic color="label" mb={2}>
                — {author}
              </Box>
              <Stack>
                <Stack.Item>
                  <Button
                    onClick={() => act('prev')}
                    disabled={page <= 1}
                    icon="chevron-left"
                  >
                    Newer
                  </Button>
                </Stack.Item>
                <Stack.Item grow textAlign="center">
                  Page <b>{page}</b> of <b>{total}</b>
                </Stack.Item>
                <Stack.Item>
                  <Button
                    onClick={() => act('next')}
                    disabled={page >= total}
                    iconPosition="right"
                    icon="chevron-right"
                  >
                    Older
                  </Button>
                </Stack.Item>
              </Stack>
            </>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
