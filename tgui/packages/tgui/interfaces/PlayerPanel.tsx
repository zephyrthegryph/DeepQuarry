// Structured TGUI admin player panel.
//
// Receives a typed list of players; renders a native React filter +
// sortable list + per-player action buttons. Replaces the legacy
// HTML+JS panel (and its lost in-browser filter).

import { useMemo, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  Input,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Player = {
  name: string;
  real_name: string;
  key: string;
  connected: BooleanLike;
  job: string;
  is_antagonist: number;
  ref: string;
  ip: string;
};

type Data = {
  players: Player[];
};

type SortKey = 'name' | 'real_name' | 'key' | 'job';

const matchesFilter = (p: Player, q: string): boolean => {
  if (!q) return true;
  const needle = q.toLowerCase();
  return (
    p.name.toLowerCase().includes(needle) ||
    p.real_name.toLowerCase().includes(needle) ||
    p.key.toLowerCase().includes(needle) ||
    p.job.toLowerCase().includes(needle)
  );
};

const compareBy = (a: Player, b: Player, key: SortKey): number => {
  const va = (a[key] || '').toLowerCase();
  const vb = (b[key] || '').toLowerCase();
  return va < vb ? -1 : va > vb ? 1 : 0;
};

export const PlayerPanel = () => {
  const { data, act } = useBackend<Data>();
  const players = data.players ?? [];
  const [filter, setFilter] = useState('');
  const [sortKey, setSortKey] = useState<SortKey>('key');

  const visible = useMemo(() => {
    return players
      .filter((p) => matchesFilter(p, filter))
      .sort((a, b) => compareBy(a, b, sortKey));
  }, [players, filter, sortKey]);

  return (
    <Window width={780} height={560} title="Admin Player Panel">
      <Window.Content scrollable>
        <Section
          title="Player Panel"
          buttons={
            <>
              <Button icon="rotate" onClick={() => act('refresh')}>
                Refresh
              </Button>{' '}
              <Button
                icon="user-secret"
                onClick={() => act('check_antagonists')}
              >
                Check Antagonists
              </Button>
            </>
          }
        >
          <Stack mb={1}>
            <Stack.Item grow>
              <Input
                fluid
                placeholder="Filter by name, real name, key, or job…"
                value={filter}
                onChange={(value) => setFilter(value)}
              />
            </Stack.Item>
            <Stack.Item color="label">
              {visible.length}/{players.length}
            </Stack.Item>
          </Stack>

          <Table>
            <Table.Row header>
              <Table.Cell>
                <Button
                  compact
                  onClick={() => setSortKey('name')}
                  selected={sortKey === 'name'}
                >
                  Name
                </Button>
              </Table.Cell>
              <Table.Cell>
                <Button
                  compact
                  onClick={() => setSortKey('real_name')}
                  selected={sortKey === 'real_name'}
                >
                  Real Name
                </Button>
              </Table.Cell>
              <Table.Cell>
                <Button
                  compact
                  onClick={() => setSortKey('job')}
                  selected={sortKey === 'job'}
                >
                  Job
                </Button>
              </Table.Cell>
              <Table.Cell>
                <Button
                  compact
                  onClick={() => setSortKey('key')}
                  selected={sortKey === 'key'}
                >
                  Key
                </Button>
              </Table.Cell>
              <Table.Cell collapsing>Actions</Table.Cell>
            </Table.Row>
            {visible.map((p) => (
              <Table.Row key={p.ref}>
                <Table.Cell>{p.name}</Table.Cell>
                <Table.Cell>{p.real_name}</Table.Cell>
                <Table.Cell color="label">{p.job}</Table.Cell>
                <Table.Cell>
                  {p.key}
                  {!p.connected ? (
                    <Box inline color="bad" ml={1}>
                      (DC)
                    </Box>
                  ) : null}
                  {p.is_antagonist ? (
                    <Box inline color="bad" bold ml={1}>
                      ★
                    </Box>
                  ) : null}
                </Table.Cell>
                <Table.Cell collapsing>
                  <Button
                    compact
                    icon="user"
                    onClick={() => act('admin_opts', { ref: p.ref })}
                    tooltip="Player options"
                  >
                    PP
                  </Button>{' '}
                  <Button
                    compact
                    icon="comment"
                    onClick={() => act('private_message', { ref: p.ref })}
                    tooltip="Private message"
                  >
                    PM
                  </Button>{' '}
                  <Button
                    compact
                    icon="user-secret"
                    color={p.is_antagonist ? 'bad' : undefined}
                    onClick={() => act('traitor', { ref: p.ref })}
                    tooltip="Traitor check"
                  >
                    ?
                  </Button>
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
      </Window.Content>
    </Window>
  );
};
