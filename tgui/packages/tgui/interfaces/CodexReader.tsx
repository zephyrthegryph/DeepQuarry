// Codex — structured TGUI reader for the lore books.
//
// The page text is lore-authored HTML (HtmlRenderer); its quick links
// (byond://?quick_link=Term) become the quick_link op. Navigation is data:
// the way up, the pages under this one and back / up / home buttons.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Input, Section, Stack } from 'tgui-core/components';
import { HtmlRenderer } from './common/HtmlRenderer';
import type {
  CodexReaderActions,
  CodexReaderData,
} from './generated/CodexReader';

type Data = CodexReaderData;

export const CodexReader = () => {
  const { data, act } = useBackend<Data, CodexReaderActions>();
  const { page_name, page_html, trail = [], children = [] } = data;
  const [query, setQuery] = useState('');
  const search = () => {
    if (query) {
      act('quick_link', { term: query });
    }
  };
  return (
    <Window width={640} height={620} title="The Empress Protects">
      <Window.Content scrollable>
        <Section>
          <Stack vertical>
            <Stack.Item>
              {trail.map((link) => (
                <Box inline key={link.id}>
                  <Button
                    compact
                    onClick={() => act('target', { page: link.id })}
                  >
                    {link.name}
                  </Button>{' '}
                  &gt;{' '}
                </Box>
              ))}
              <Box inline bold>
                {page_name}
              </Box>
            </Stack.Item>
            <Stack.Item>
              <Input
                placeholder="Page Search"
                value={query}
                onChange={setQuery}
                onEnter={search}
              />{' '}
              <Button onClick={search}>Go</Button>
            </Stack.Item>
          </Stack>
        </Section>
        <Section title={page_name}>
          {page_html ? (
            <Box mb={1}>
              <HtmlRenderer
                html={page_html}
                onLinkAction={(action, params) => {
                  if (action === 'quick_link') {
                    act('quick_link', { term: params.quick_link });
                  }
                }}
              />
            </Box>
          ) : null}
          {children.length > 0 ? (
            <Stack wrap>
              {children.map((child) => (
                <Stack.Item key={child.id}>
                  <Button onClick={() => act('target', { page: child.id })}>
                    {child.name}
                  </Button>
                </Stack.Item>
              ))}
            </Stack>
          ) : null}
        </Section>
        <Section>
          <Stack>
            {data.can_back ? (
              <Stack.Item>
                <Button icon="arrow-left" onClick={() => act('go_back')}>
                  Go Back
                </Button>
              </Stack.Item>
            ) : null}
            {data.can_up ? (
              <Stack.Item>
                <Button icon="arrow-up" onClick={() => act('go_to_parent')}>
                  Go Up
                </Button>
              </Stack.Item>
            ) : null}
            {data.can_home ? (
              <Stack.Item>
                <Button icon="home" onClick={() => act('go_to_home')}>
                  Go To Home
                </Button>
              </Stack.Item>
            ) : null}
            <Stack.Item>
              <Button onClick={() => act('close')}>Close</Button>
            </Stack.Item>
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};
