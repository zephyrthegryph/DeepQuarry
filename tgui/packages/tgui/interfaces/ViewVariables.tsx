// View Variables — structured TGUI shell around the legacy per-variable HTML.
//
// The variable list still ships HTML per-row (vv_get_var output is
// type-specific and spans dozens of overrides); HtmlRenderer renders it and
// forwards every byond:// click as a forward_topic act so E/C/M edits keep
// working. The chrome (header, sprite metadata, marker flags, refresh,
// dropdown, search) is fully structured.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Input, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';
import { HtmlRenderer } from './common/HtmlRenderer';

type DropdownEntry = {
  name: string;
  link: string;
  is_separator: BooleanLike;
};

type Variable = {
  index?: number;
  name: string;
  value_html: string;
};

type Coords = { x: number; y: number; z: number };

type Data = {
  has_target: BooleanLike;
  is_list?: BooleanLike;
  type?: string;
  ref?: string;
  ref_for_paste?: string;
  title?: string;
  coords?: Coords | null;
  marked?: BooleanLike;
  tagged_index?: number;
  varedited?: BooleanLike;
  gc_destroyed?: BooleanLike;
  header?: string[];
  dropdown?: DropdownEntry[];
  variables?: Variable[];
};

type ActFn = (a: string, p?: Record<string, any>) => void;

const Header = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section
      title={
        <Box>
          <Box bold inline>
            {data.type}
          </Box>{' '}
          <Box inline color="label">
            {data.ref_for_paste}
          </Box>
        </Box>
      }
      buttons={
        <Button onClick={() => act('refresh')} icon="rotate-right">
          Refresh
        </Button>
      }
    >
      {data.header && data.header.length > 0 ? (
        <Box mb={1}>
          <HtmlRenderer html={data.header.join('')} act={act} forwardTopic />
        </Box>
      ) : null}
      <Box>
        {data.marked ? (
          <Box inline color="bad" bold>
            [MARKED]{' '}
          </Box>
        ) : null}
        {data.tagged_index ? (
          <Box inline color="average" bold>
            [TAGGED #{data.tagged_index}]{' '}
          </Box>
        ) : null}
        {data.varedited ? (
          <Box inline color="average" bold>
            [VAR-EDITED]{' '}
          </Box>
        ) : null}
        {data.gc_destroyed ? (
          <Box inline color="bad" bold>
            [DELETED]{' '}
          </Box>
        ) : null}
      </Box>
      {data.coords ? (
        <Box mt={1} color="label">
          x: {data.coords.x} y: {data.coords.y} z: {data.coords.z}
        </Box>
      ) : null}
    </Section>
  );
};

const DropdownSection = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  if (!data.dropdown || data.dropdown.length === 0) {
    return null;
  }
  // Build display-name → link map; preserve separators as visual breaks.
  const real_options = data.dropdown.filter((d) => !d.is_separator);
  if (real_options.length === 0) {
    return null;
  }
  return (
    <Section title="Actions">
      <Stack wrap>
        {real_options.map((o) => (
          <Stack.Item key={`${o.name}-${o.link}`}>
            <Button
              compact
              disabled={!o.link}
              onClick={() => act('dropdown_select', { link: o.link })}
            >
              {o.name}
            </Button>
          </Stack.Item>
        ))}
      </Stack>
    </Section>
  );
};

const VariableLegend = () => (
  <Section>
    <Box color="label" italic style={{ fontSize: '0.85em' }}>
      <Box>
        <b>E</b> — Edit, tries to determine the variable type by itself.
      </Box>
      <Box>
        <b>C</b> — Change, asks you for the var type first.
      </Box>
      <Box>
        <b>M</b> — Mass modify: changes this variable for all objects of this
        type.
      </Box>
    </Box>
  </Section>
);

const Variables = (props: { variables: Variable[]; act: ActFn }) => {
  const { variables, act } = props;
  const [filter, setFilter] = useState('');
  const filtered = filter
    ? variables.filter((v) =>
        `${v.name} ${v.value_html}`
          .toLowerCase()
          .includes(filter.toLowerCase()),
      )
    : variables;
  return (
    <Section
      title={`Variables (${variables.length})`}
      buttons={
        <Input
          value={filter}
          placeholder="filter…"
          onChange={(v) => setFilter(v)}
          width="240px"
        />
      }
    >
      {filtered.length === 0 ? (
        <EmptyState>(no matches)</EmptyState>
      ) : (
        <Stack vertical>
          {filtered.map((v, i) => (
            <Stack.Item key={`${v.name}-${i}`}>
              <HtmlRenderer html={v.value_html} act={act} forwardTopic />
            </Stack.Item>
          ))}
        </Stack>
      )}
    </Section>
  );
};

export const ViewVariables = () => {
  const { data, act } = useBackend<Data>();
  if (!data.has_target) {
    return (
      <Window width={680} height={400} title="Variables">
        <Window.Content>
          <Section>
            <EmptyState>No target.</EmptyState>
          </Section>
        </Window.Content>
      </Window>
    );
  }
  return (
    <Window width={760} height={720} title={data.title ?? 'Variables'}>
      <Window.Content scrollable>
        <Header data={data} act={act} />
        <DropdownSection data={data} act={act} />
        <VariableLegend />
        {data.variables ? (
          <Variables variables={data.variables} act={act} />
        ) : null}
      </Window.Content>
    </Window>
  );
};
