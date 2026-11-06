// The admin verb browser: every verb this admin's rights allow, searchable,
// with per-admin pins (the short list the verb panel shows), recently used
// verbs, and the server settings as one checkbox panel.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  Input,
  NoticeBox,
  Section,
  Stack,
  Tabs,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import {
  categoryCounts,
  filterToggles,
  filterVerbs,
  groupBySub,
  groupToggles,
  pick,
  type ToggleRow,
  type VerbRow,
} from './logic';

type Data = {
  verbs: VerbRow[];
  defaults: string[];
  pins: string[];
  recent: string[];
  toggles: (Omit<ToggleRow, 'value' | 'can'> & {
    value: BooleanLike;
    can: BooleanLike;
  })[];
};

type Page = 'browse' | 'pinned' | 'recent' | 'settings';

const VerbRowView = (props: { verb: VerbRow; pinned: boolean }) => {
  const { act } = useBackend<Data>();
  const { verb, pinned } = props;
  return (
    <Stack align="center" className="AdminVerbBrowser__row">
      <Stack.Item>
        <Button
          compact
          icon={pinned ? 'star' : 'star-half-stroke'}
          color={pinned ? 'yellow' : 'transparent'}
          tooltip={
            pinned ? 'Unpin from the verb panel' : 'Pin to the verb panel'
          }
          onClick={() => act('toggle_pin', { id: verb.id })}
        />
      </Stack.Item>
      <Stack.Item basis="35%">
        <Button
          fluid
          ellipsis
          icon="play"
          tooltip={verb.cat}
          onClick={() => act('run_verb', { id: verb.id })}
        >
          {verb.name}
        </Button>
      </Stack.Item>
      <Stack.Item grow color="label">
        {verb.desc}
      </Stack.Item>
    </Stack>
  );
};

const VerbList = (props: {
  verbs: VerbRow[];
  pins: string[];
  flat?: boolean;
}) => {
  const { verbs, pins, flat } = props;
  if (!verbs.length) {
    return <NoticeBox info>No verbs here.</NoticeBox>;
  }
  const pinSet = new Set(pins);
  if (flat) {
    return (
      <Section>
        {verbs.map((verb) => (
          <VerbRowView key={verb.id} verb={verb} pinned={pinSet.has(verb.id)} />
        ))}
      </Section>
    );
  }
  return (
    <>
      {groupBySub(verbs).map(({ sub, verbs: group }) => (
        <Section key={sub || 'top'} title={sub || undefined}>
          {group.map((verb) => (
            <VerbRowView
              key={verb.id}
              verb={verb}
              pinned={pinSet.has(verb.id)}
            />
          ))}
        </Section>
      ))}
    </>
  );
};

const Settings = (props: { toggles: Data['toggles']; query: string }) => {
  const { act } = useBackend<Data>();
  const rows: ToggleRow[] = props.toggles.map((toggle) => ({
    ...toggle,
    value: !!toggle.value,
    can: !!toggle.can,
  }));
  const shown = filterToggles(rows, props.query);
  if (!shown.length) {
    return <NoticeBox info>No server settings match.</NoticeBox>;
  }
  return (
    <>
      {groupToggles(shown).map(({ group, rows: list }) => (
        <Section key={group} title={group}>
          {list.map((toggle) => (
            <Box key={toggle.id} className="AdminVerbBrowser__row">
              <Button.Checkbox
                checked={toggle.value}
                disabled={!toggle.can}
                onClick={() => act('toggle_setting', { id: toggle.id })}
              >
                {toggle.label}
              </Button.Checkbox>
              {toggle.desc ? (
                <Box inline color="label" ml={1}>
                  {toggle.desc}
                </Box>
              ) : null}
            </Box>
          ))}
        </Section>
      ))}
    </>
  );
};

export const AdminVerbBrowser = () => {
  const { act, data } = useBackend<Data>();
  const { verbs, pins, recent, defaults, toggles } = data;
  const [query, setQuery] = useState('');
  const [page, setPage] = useState<Page>('browse');
  const [category, setCategory] = useState<string | null>(null);

  const searching = query.trim().length > 0;
  const counts = categoryCounts(verbs);

  const verbsForPage = (): VerbRow[] => {
    if (page === 'pinned') return filterVerbs(pick(verbs, pins), query, null);
    if (page === 'recent') {
      // Most recent first, not name order.
      return pick(verbs, recent).filter(
        (verb) => filterVerbs([verb], query, null).length,
      );
    }
    return filterVerbs(verbs, query, searching ? null : category);
  };

  return (
    <Window width={860} height={640} title="Admin Verbs" theme="console">
      <Window.Content>
        <Stack vertical fill>
          <Stack.Item>
            <Stack>
              <Stack.Item grow>
                <Input
                  fluid
                  placeholder="Search verbs by name or description..."
                  value={query}
                  onChange={(value) => setQuery(value)}
                />
              </Stack.Item>
              <Stack.Item color="label">
                {verbs.length} verbs / {pins.length} pinned
              </Stack.Item>
              <Stack.Item>
                <Button
                  icon="rotate-left"
                  tooltip={`Pin the default set again (${defaults.length} verbs)`}
                  onClick={() => act('reset_pins')}
                >
                  Default pins
                </Button>
              </Stack.Item>
            </Stack>
          </Stack.Item>
          <Stack.Item>
            <Tabs>
              <Tabs.Tab
                selected={page === 'browse'}
                onClick={() => setPage('browse')}
              >
                Browse
              </Tabs.Tab>
              <Tabs.Tab
                selected={page === 'pinned'}
                onClick={() => setPage('pinned')}
              >
                Pinned
              </Tabs.Tab>
              <Tabs.Tab
                selected={page === 'recent'}
                onClick={() => setPage('recent')}
              >
                Recent
              </Tabs.Tab>
              <Tabs.Tab
                selected={page === 'settings'}
                onClick={() => setPage('settings')}
              >
                Server settings
              </Tabs.Tab>
            </Tabs>
          </Stack.Item>
          <Stack.Item grow>
            <Stack fill>
              {page === 'browse' && !searching ? (
                <Stack.Item basis="22%">
                  <Section fill scrollable>
                    <Tabs vertical>
                      <Tabs.Tab
                        selected={category === null}
                        onClick={() => setCategory(null)}
                      >
                        All ({verbs.length})
                      </Tabs.Tab>
                      {counts.map(([name, count]) => (
                        <Tabs.Tab
                          key={name}
                          selected={category === name}
                          onClick={() => setCategory(name)}
                        >
                          {name} ({count})
                        </Tabs.Tab>
                      ))}
                    </Tabs>
                  </Section>
                </Stack.Item>
              ) : null}
              <Stack.Item grow>
                <Section fill scrollable>
                  {page === 'settings' ? (
                    <Settings toggles={toggles} query={query} />
                  ) : (
                    <VerbList
                      verbs={verbsForPage()}
                      pins={pins}
                      flat={page === 'recent'}
                    />
                  )}
                </Section>
              </Stack.Item>
            </Stack>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
