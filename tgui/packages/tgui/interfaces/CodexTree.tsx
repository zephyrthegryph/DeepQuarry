// In-world lore codex tree — TGUI.
//
// Hierarchical page reader. Page selection and history are tracked DM-side
// per-user; this component just shows the current state and routes
// navigation actions.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Input, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { HtmlRenderer } from './common/HtmlRenderer';

type Crumb = {
  ref: string;
  name: string;
};

type Child = {
  ref: string;
  name: string;
};

type Data = {
  holder_name: string;
  page_name: string;
  page_data: string;
  crumbs: Crumb[];
  children: Child[];
  is_category: BooleanLike;
  can_go_back: BooleanLike;
  can_go_up: BooleanLike;
  can_go_home: BooleanLike;
};

export const CodexTree = () => {
  const { data, act } = useBackend<Data>();
  const {
    holder_name,
    page_name,
    page_data,
    crumbs,
    children,
    is_category,
    can_go_back,
    can_go_up,
    can_go_home,
  } = data;
  const [search, setSearch] = useState('');

  return (
    <Window width={620} height={600} title={`${holder_name} (${page_name})`}>
      <Window.Content scrollable>
        <Box mb={1}>
          {crumbs.map((c, i) => (
            <Box inline key={c.ref}>
              {i > 0 ? (
                <Box inline color="label" mx="4px">
                  {'>'}
                </Box>
              ) : null}
              <Button compact onClick={() => act('target', { ref: c.ref })}>
                {c.name}
              </Button>
            </Box>
          ))}
        </Box>

        <Box mb={1}>
          <Input
            placeholder="Search…"
            value={search}
            onChange={(v) => setSearch(v)}
            onEnter={(_, v) => {
              if (v) {
                act('search', { query: v });
                setSearch('');
              }
            }}
          />
        </Box>

        <Section title={page_name}>
          {page_data ? (
            <HtmlRenderer
              html={page_data}
              onLinkAction={(action, params) => {
                if (action === 'quick_link' && params.quick_link) {
                  act('search', { query: params.quick_link });
                } else if (action === 'target' && params.target) {
                  act('target', { ref: params.target });
                }
              }}
            />
          ) : null}

          {is_category && children.length > 0 ? (
            <Box mt={1}>
              <Stack vertical>
                {children.map((c) => (
                  <Stack.Item key={c.ref}>
                    <Button fluid onClick={() => act('target', { ref: c.ref })}>
                      {c.name}
                    </Button>
                  </Stack.Item>
                ))}
              </Stack>
            </Box>
          ) : null}

          <Box mt={2}>
            {can_go_back ? (
              <Button icon="arrow-left" onClick={() => act('go_back')}>
                Back
              </Button>
            ) : null}{' '}
            {can_go_up ? (
              <Button icon="level-up-alt" onClick={() => act('go_up')}>
                Up
              </Button>
            ) : null}{' '}
            {can_go_home ? (
              <Button icon="home" onClick={() => act('go_home')}>
                Home
              </Button>
            ) : null}
          </Box>
        </Section>
      </Window.Content>
    </Window>
  );
};
