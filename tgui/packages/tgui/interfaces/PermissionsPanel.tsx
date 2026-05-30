// Admin Permissions Panel — structured TGUI for the 4-tab editor.
// Pages: Permissions (admin list), Ranks, Logging, Housekeeping.
//
// All actions dispatch through the existing /datum/admins.Topic handlers
// (editrights*, editrightsbrowser*) so the legacy DB writes and the
// per-admin / per-rank workflows keep working unchanged. Logging search
// state is owned by the panel datum — the React side just submits inputs.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  Dropdown,
  Input,
  LabeledList,
  Section,
  Stack,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type AdminRow = {
  ckey: string;
  rank: string;
  permissions: string;
  deadmined: BooleanLike;
};

type RankRow = {
  name: string;
  source: string;
  held_by: number;
  permissions: string;
  denied: string;
  editable: string;
  can_modify: BooleanLike;
  can_delete: BooleanLike;
};

type RanksPageData = {
  rows: RankRow[];
  can_create: BooleanLike;
};

type LogEntry = {
  datetime: string;
  round_id: string;
  admin_key: string;
  operation: string;
  ckey_actioned: string;
  log: string;
};

type LoggingPageData = {
  log_target: string;
  log_actor: string;
  log_operation: string;
  log_page: number;
  log_count: number;
  per_page: number;
  action_options: string[];
  entries: LogEntry[];
};

type HousekeepingPageData = {
  invalid_admins: { admin: string; rank: string }[];
  unused_ranks: {
    name: string;
    source: string;
    permissions: string;
    denied: string;
    editable: string;
    can_delete: BooleanLike;
  }[];
};

type Data = {
  page: string;
  PERMISSIONS_PAGE_PERMISSIONS: string;
  PERMISSIONS_PAGE_RANKS: string;
  PERMISSIONS_PAGE_LOGGING: string;
  PERMISSIONS_PAGE_HOUSEKEEPING: string;
  permissions_rows?: AdminRow[];
  ranks_page?: RanksPageData;
  logging_page?: LoggingPageData;
  housekeeping_page?: HousekeepingPageData;
};

type ActFn = (a: string, p?: Record<string, any>) => void;

const PageNav = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section>
      <Button
        selected={data.page === data.PERMISSIONS_PAGE_PERMISSIONS}
        onClick={() => act('nav_permissions')}
      >
        Permissions
      </Button>{' '}
      <Button
        selected={data.page === data.PERMISSIONS_PAGE_RANKS}
        onClick={() => act('nav_ranks')}
      >
        Ranks
      </Button>{' '}
      <Button
        selected={data.page === data.PERMISSIONS_PAGE_LOGGING}
        onClick={() => act('nav_logging')}
      >
        Logging
      </Button>{' '}
      <Button
        selected={data.page === data.PERMISSIONS_PAGE_HOUSEKEEPING}
        onClick={() => act('nav_housekeeping')}
      >
        Housekeeping
      </Button>
    </Section>
  );
};

const PermissionsPage = (props: { rows: AdminRow[]; act: ActFn }) => {
  const { rows, act } = props;
  const [filter, setFilter] = useState('');
  const filtered = filter
    ? rows.filter(
        (r) =>
          r.ckey.toLowerCase().includes(filter.toLowerCase()) ||
          r.rank.toLowerCase().includes(filter.toLowerCase()),
      )
    : rows;
  return (
    <Section
      title={`Admins (${rows.length})`}
      buttons={
        <>
          <Input
            value={filter}
            placeholder="Search ckey / rank…"
            onChange={(value) => setFilter(value)}
            width="200px"
          />{' '}
          <Button color="good" icon="plus" onClick={() => act('admin_add')}>
            Add
          </Button>
        </>
      }
    >
      <Stack vertical>
        {filtered.map((r) => (
          <Stack.Item key={r.ckey}>
            <Box>
              <Box inline bold>
                {r.ckey}
              </Box>{' '}
              {r.deadmined ? (
                <Button
                  compact
                  color="good"
                  onClick={() => act('admin_activate', { key: r.ckey })}
                >
                  RA
                </Button>
              ) : (
                <Button
                  compact
                  color="bad"
                  onClick={() => act('admin_deactivate', { key: r.ckey })}
                >
                  DA
                </Button>
              )}{' '}
              <Button
                compact
                color="bad"
                onClick={() => act('admin_remove', { key: r.ckey })}
              >
                Remove
              </Button>{' '}
              <Button
                compact
                onClick={() => act('admin_sync', { key: r.ckey })}
              >
                Sync TGDB
              </Button>
            </Box>
            <Box ml={1}>
              <Button
                compact
                onClick={() => act('admin_rank', { key: r.ckey })}
              >
                {r.rank}
              </Button>
            </Box>
            <Box ml={1}>
              <Button
                compact
                onClick={() => act('admin_permissions', { key: r.ckey })}
                tooltip={r.permissions}
              >
                <Box style={{ fontFamily: 'monospace', fontSize: '0.85em' }}>
                  {r.permissions || '(no permissions)'}
                </Box>
              </Button>
            </Box>
          </Stack.Item>
        ))}
      </Stack>
    </Section>
  );
};

const RanksPage = (props: { data: RanksPageData; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section
      title={`Ranks (${data.rows.length})`}
      buttons={
        data.can_create ? (
          <Button color="good" icon="plus" onClick={() => act('ranks_create')}>
            Create Rank
          </Button>
        ) : null
      }
    >
      <Stack vertical>
        {data.rows.map((r) => (
          <Stack.Item key={r.name}>
            <Box>
              <Box inline bold>
                {r.name}
              </Box>{' '}
              {r.can_modify ? (
                <Button
                  compact
                  onClick={() => act('ranks_edit', { name: r.name })}
                >
                  Edit
                </Button>
              ) : null}{' '}
              {r.can_delete ? (
                <Button
                  compact
                  color="bad"
                  onClick={() => act('ranks_delete', { name: r.name })}
                >
                  Delete
                </Button>
              ) : null}
            </Box>
            <Box ml={1} color="label">
              Source: {r.source} · Held by {r.held_by}
            </Box>
            <Box ml={1} style={{ fontFamily: 'monospace', fontSize: '0.85em' }}>
              <Box>Permissions: {r.permissions}</Box>
              {r.denied ? <Box>Denied: {r.denied}</Box> : null}
              {r.editable ? <Box>Allowed to edit: {r.editable}</Box> : null}
            </Box>
          </Stack.Item>
        ))}
      </Stack>
    </Section>
  );
};

const LoggingPage = (props: { data: LoggingPageData; act: ActFn }) => {
  const { data, act } = props;
  const [target, setTarget] = useState(data.log_target);
  const [actor, setActor] = useState(data.log_actor);
  const [op, setOp] = useState(data.log_operation);
  const total_pages = Math.max(1, Math.ceil(data.log_count / data.per_page));
  const pages = Array.from({ length: total_pages }, (_, i) => i);
  return (
    <>
      <Section title="Filters">
        <Stack>
          <Stack.Item>
            <LabeledList>
              <LabeledList.Item label="Ckey Modified">
                <Input
                  value={target}
                  onChange={(v) => setTarget(v)}
                  width="200px"
                />
              </LabeledList.Item>
              <LabeledList.Item label="Acting Admin">
                <Input
                  value={actor}
                  onChange={(v) => setActor(v)}
                  width="200px"
                />
              </LabeledList.Item>
              <LabeledList.Item label="Action">
                <Dropdown
                  selected={op}
                  options={data.action_options}
                  onSelected={(v) => setOp(v)}
                  width="220px"
                />
              </LabeledList.Item>
            </LabeledList>
          </Stack.Item>
        </Stack>
        <Box mt={1}>
          <Button
            color="good"
            icon="search"
            onClick={() => act('log_search', { target, actor, operation: op })}
          >
            Search
          </Button>
        </Box>
      </Section>
      <Section title={`Results — ${data.log_count} matches`}>
        {total_pages > 1 ? (
          <Box mb={1}>
            Page:{' '}
            {pages.map((p) => (
              <Button
                key={p}
                compact
                selected={p === data.log_page}
                onClick={() => act('log_page', { page: p })}
              >
                {p}
              </Button>
            ))}
          </Box>
        ) : null}
        <Stack vertical>
          {data.entries.length === 0 ? (
            <Stack.Item>
              <EmptyState>No log entries match.</EmptyState>
            </Stack.Item>
          ) : (
            data.entries.map((e, i) => (
              <Stack.Item key={`${e.datetime}-${i}`}>
                <Box bold>
                  {e.datetime} | Round {e.round_id} | Admin {e.admin_key} |{' '}
                  {e.operation} on {e.ckey_actioned}
                </Box>
                <Box ml={1} style={{ whiteSpace: 'pre-wrap' }}>
                  {e.log}
                </Box>
              </Stack.Item>
            ))
          )}
        </Stack>
      </Section>
    </>
  );
};

const HousekeepingPage = (props: {
  data: HousekeepingPageData;
  act: ActFn;
}) => {
  const { data, act } = props;
  return (
    <>
      <Section
        title={`Admins with invalid ranks (${data.invalid_admins.length})`}
      >
        {data.invalid_admins.length === 0 ? (
          <EmptyState>No invalid ranks found.</EmptyState>
        ) : (
          <Stack vertical>
            {data.invalid_admins.map((row, i) => (
              <Stack.Item key={`${row.admin}-${i}`}>
                <Box>
                  <Box inline bold>
                    {row.admin}
                  </Box>{' '}
                  has the non-existent rank{' '}
                  <Box inline color="bad">
                    {row.rank}
                  </Box>{' '}
                  <Button
                    compact
                    onClick={() =>
                      act('housekeep_change', { admin: row.admin })
                    }
                  >
                    Change Rank
                  </Button>{' '}
                  <Button
                    compact
                    color="bad"
                    onClick={() =>
                      act('housekeep_remove_admin', { admin: row.admin })
                    }
                  >
                    Remove
                  </Button>
                </Box>
              </Stack.Item>
            ))}
          </Stack>
        )}
      </Section>
      <Section title={`Unused DB ranks (${data.unused_ranks.length})`}>
        {data.unused_ranks.length === 0 ? (
          <EmptyState>No unused ranks found.</EmptyState>
        ) : (
          <Stack vertical>
            {data.unused_ranks.map((r) => (
              <Stack.Item key={r.name}>
                <Box>
                  <Box inline bold>
                    {r.name}
                  </Box>{' '}
                  not held by any admin{' '}
                  {r.can_delete ? (
                    <Button
                      compact
                      color="bad"
                      onClick={() =>
                        act('housekeep_remove_rank', { name: r.name })
                      }
                    >
                      Delete
                    </Button>
                  ) : null}
                </Box>
                <Box ml={1} color="label">
                  Source: {r.source}
                </Box>
                <Box
                  ml={1}
                  style={{ fontFamily: 'monospace', fontSize: '0.85em' }}
                >
                  <Box>Permissions: {r.permissions}</Box>
                  {r.denied ? <Box>Denied: {r.denied}</Box> : null}
                  {r.editable ? <Box>Allowed to edit: {r.editable}</Box> : null}
                </Box>
              </Stack.Item>
            ))}
          </Stack>
        )}
      </Section>
    </>
  );
};

export const PermissionsPanel = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Window width={820} height={720} title="Permissions">
      <Window.Content scrollable>
        <PageNav data={data} act={act} />
        {data.page === data.PERMISSIONS_PAGE_PERMISSIONS &&
        data.permissions_rows ? (
          <PermissionsPage rows={data.permissions_rows} act={act} />
        ) : null}
        {data.page === data.PERMISSIONS_PAGE_RANKS && data.ranks_page ? (
          <RanksPage data={data.ranks_page} act={act} />
        ) : null}
        {data.page === data.PERMISSIONS_PAGE_LOGGING && data.logging_page ? (
          <LoggingPage data={data.logging_page} act={act} />
        ) : null}
        {data.page === data.PERMISSIONS_PAGE_HOUSEKEEPING &&
        data.housekeeping_page ? (
          <HousekeepingPage data={data.housekeeping_page} act={act} />
        ) : null}
      </Window.Content>
    </Window>
  );
};
