// Error Viewer — structured TGUI replacement for the legacy multi-screen
// runtime browser.
//
// view_kind discriminates layout:
//   - "cache":  list of error sources or chronological errors (toggle via mode)
//   - "source": list of error entries belonging to one source
//   - "entry":  full detail of a single error including usr/loc admin links

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';
import { HtmlRenderer } from './common/HtmlRenderer';

type Item = {
  ref: string;
  name: string;
  is_skip_count: BooleanLike;
};

type Data = {
  view_kind: 'cache' | 'source' | 'entry' | 'unknown';
  title: string;
  back_ref: string | null;
  linear: BooleanLike;
  total_runtimes: number;
  total_skipped: number;
  // cache | source
  items?: Item[];
  // entry
  desc?: string;
  usr_ref?: string | null;
  usr_loc_ref?: string | null;
  usr_loc_x?: number;
  usr_loc_y?: number;
  usr_loc_z?: number;
};

const Header = (props: { data: Data; act: (a: string, p?: any) => void }) => {
  const { data, act } = props;
  return (
    <Section>
      <Stack>
        {data.back_ref ? (
          <Stack.Item>
            <Button onClick={() => act('back')} icon="chevron-left">
              Back
            </Button>
          </Stack.Item>
        ) : null}
        <Stack.Item>
          <Button onClick={() => act('refresh')} icon="rotate-right">
            Refresh
          </Button>
        </Stack.Item>
        <Stack.Item grow textAlign="right">
          <Box color="label">
            <b>{data.total_runtimes}</b> runtimes, <b>{data.total_skipped}</b>{' '}
            skipped
          </Box>
        </Stack.Item>
      </Stack>
    </Section>
  );
};

const ItemList = (props: {
  items: Item[];
  onSelect: (ref: string) => void;
}) => {
  const { items, onSelect } = props;
  if (items.length === 0) {
    return <EmptyState>(no entries)</EmptyState>;
  }
  return (
    <Stack vertical>
      {items.map((it) => (
        <Stack.Item key={it.ref}>
          {it.is_skip_count ? (
            <Box color="label">
              <HtmlRenderer html={it.name} />
            </Box>
          ) : (
            <Button onClick={() => onSelect(it.ref)}>
              <HtmlRenderer html={it.name} />
            </Button>
          )}
        </Stack.Item>
      ))}
    </Stack>
  );
};

const CacheView = (props: {
  data: Data;
  act: (a: string, p?: any) => void;
}) => {
  const { data, act } = props;
  return (
    <Section
      title="Error Cache"
      buttons={
        <>
          <Button
            compact
            selected={!data.linear}
            onClick={() => act('set_mode', { mode: 'organized' })}
          >
            Organized
          </Button>{' '}
          <Button
            compact
            selected={!!data.linear}
            onClick={() => act('set_mode', { mode: 'linear' })}
          >
            Linear
          </Button>
        </>
      }
    >
      <ItemList
        items={data.items ?? []}
        onSelect={(ref) => act('navigate', { ref })}
      />
    </Section>
  );
};

const SourceView = (props: {
  data: Data;
  act: (a: string, p?: any) => void;
}) => {
  const { data, act } = props;
  return (
    <Section title="Error Source">
      <Box mb={1}>
        <HtmlRenderer html={data.title} />
      </Box>
      <ItemList
        items={data.items ?? []}
        onSelect={(ref) => act('navigate', { ref })}
      />
    </Section>
  );
};

const EntryView = (props: {
  data: Data;
  act: (a: string, p?: any) => void;
}) => {
  const { data, act } = props;
  return (
    <Section title="Error Entry">
      <Box mb={1}>
        <HtmlRenderer html={data.title} />
      </Box>
      {data.desc ? (
        <Section title="Stack" fitted>
          <Box style={{ fontFamily: 'monospace', whiteSpace: 'pre-wrap' }}>
            <HtmlRenderer html={data.desc} />
          </Box>
        </Section>
      ) : null}
      {data.usr_ref ? (
        <Section title="usr">
          <LabeledList>
            <LabeledList.Item label="Actions">
              <Button compact onClick={() => act('vv_usr')}>
                VV
              </Button>{' '}
              <Button compact onClick={() => act('pp_usr')}>
                PP
              </Button>{' '}
              <Button compact onClick={() => act('follow_usr')}>
                Follow
              </Button>
            </LabeledList.Item>
            {data.usr_loc_ref ? (
              <LabeledList.Item label="usr.loc">
                <Button compact onClick={() => act('vv_usr_loc')}>
                  VV
                </Button>{' '}
                <Button compact onClick={() => act('jmp_usr_loc')}>
                  JMP ({data.usr_loc_x}, {data.usr_loc_y}, {data.usr_loc_z})
                </Button>
              </LabeledList.Item>
            ) : null}
          </LabeledList>
        </Section>
      ) : null}
    </Section>
  );
};

export const ErrorViewer = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Window width={720} height={680} title="Error Viewer">
      <Window.Content scrollable>
        <Header data={data} act={act} />
        {data.view_kind === 'cache' ? (
          <CacheView data={data} act={act} />
        ) : null}
        {data.view_kind === 'source' ? (
          <SourceView data={data} act={act} />
        ) : null}
        {data.view_kind === 'entry' ? (
          <EntryView data={data} act={act} />
        ) : null}
      </Window.Content>
    </Window>
  );
};
