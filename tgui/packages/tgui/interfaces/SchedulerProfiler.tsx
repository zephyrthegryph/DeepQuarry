import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Button,
  Input,
  LabeledList,
  NoticeBox,
  Section,
  Table,
  Tabs,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Behaviour = {
  name: string;
  type: string;
  lane: string;
  runs: number;
  ms: number;
  ms_per_s: number;
  us_per_run: number;
  call_max_ms: number;
  late_max: number;
  deferrals: number;
  breaches: number;
  errors: number;
  wakes: number;
  parks: number;
  population: number;
  parked: number;
};

type Lane = {
  name: string;
  share: number;
  behaviours: number;
  runs: number;
  ms: number;
  ms_per_s: number;
  wake_queue: number;
  world_queue: number;
};

type Service = {
  name: string;
  type: string;
  initialized: BooleanLike;
  on_demand: BooleanLike;
  parked: BooleanLike;
  resuming: BooleanLike;
  steps: number;
  ms: number;
  ms_per_s: number;
  avg_ms: number;
  status: string;
};

type WorldStep = {
  step_ms: number;
  total_wakes: number;
  last_wakes: number;
  dropped: number;
};

type Stage = {
  key: string;
  calls: number;
  ms: number;
  us_per_call: number;
};

type Cache = {
  name: string;
  hits: number | null;
  misses: number;
  hit_rate: number;
  entries: number;
  max_entries: number;
  evictions: number;
  invalidations: number;
  kb: number;
  policy: string;
};

type Data = {
  elapsed_s: number;
  last_run_ms: number;
  error_count: number;
  behind: BooleanLike;
  shared_bucket: BooleanLike;
  behaviours: Behaviour[];
  lanes: Lane[];
  stages: Stage[];
  services: Service[];
  caches?: Cache[];
  world_step?: WorldStep;
};

type SortKey = 'ms' | 'runs' | 'us_per_run' | 'errors';

export const OmProfiler = (props) => {
  const { act, data } = useBackend<Data>();
  const { elapsed_s, last_run_ms, error_count, behind, shared_bucket } = data;
  const [tab, setTab] = useState(0);
  return (
    <Window width={900} height={640}>
      <Window.Content scrollable>
        <Section
          title="Scheduler"
          buttons={
            <Button icon="undo" onClick={() => act('reset')}>
              Reset counters
            </Button>
          }
        >
          <LabeledList>
            <LabeledList.Item label="Window">{elapsed_s} s</LabeledList.Item>
            <LabeledList.Item label="Last pass">
              {last_run_ms} ms{behind ? ' (behind)' : ''}
            </LabeledList.Item>
            <LabeledList.Item label="Errors">{error_count}</LabeledList.Item>
          </LabeledList>
          {!!shared_bucket && (
            <NoticeBox>
              Behaviour ids past the stat table size share one bucket; their
              rows repeat the same numbers.
            </NoticeBox>
          )}
        </Section>
        <Tabs>
          <Tabs.Tab selected={tab === 0} onClick={() => setTab(0)}>
            Lanes
          </Tabs.Tab>
          <Tabs.Tab selected={tab === 1} onClick={() => setTab(1)}>
            Behaviours
          </Tabs.Tab>
          <Tabs.Tab selected={tab === 2} onClick={() => setTab(2)}>
            Pipeline stages
          </Tabs.Tab>
          <Tabs.Tab selected={tab === 3} onClick={() => setTab(3)}>
            World services
          </Tabs.Tab>
          <Tabs.Tab selected={tab === 4} onClick={() => setTab(4)}>
            Caches
          </Tabs.Tab>
        </Tabs>
        {tab === 0 && <LanesTab />}
        {tab === 1 && <BehavioursTab />}
        {tab === 2 && <StagesTab />}
        {tab === 3 && <ServicesTab />}
        {tab === 4 && <CachesTab />}
      </Window.Content>
    </Window>
  );
};

const LanesTab = (props) => {
  const { data } = useBackend<Data>();
  const { lanes = [] } = data;
  return (
    <Section>
      <Table>
        <Table.Row header>
          <Table.Cell>Lane</Table.Cell>
          <Table.Cell>Budget share</Table.Cell>
          <Table.Cell>Behaviours</Table.Cell>
          <Table.Cell>Runs</Table.Cell>
          <Table.Cell>Total ms</Table.Cell>
          <Table.Cell>ms/s</Table.Cell>
          <Table.Cell>Wakes queued</Table.Cell>
          <Table.Cell>World wakes queued</Table.Cell>
        </Table.Row>
        {lanes.map((lane) => (
          <Table.Row key={lane.name}>
            <Table.Cell>{lane.name}</Table.Cell>
            <Table.Cell>{Math.round(lane.share * 100)}%</Table.Cell>
            <Table.Cell>{lane.behaviours}</Table.Cell>
            <Table.Cell>{lane.runs}</Table.Cell>
            <Table.Cell>{lane.ms}</Table.Cell>
            <Table.Cell>{lane.ms_per_s}</Table.Cell>
            <Table.Cell>{lane.wake_queue}</Table.Cell>
            <Table.Cell>{lane.world_queue}</Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

const BehavioursTab = (props) => {
  const { data } = useBackend<Data>();
  const { behaviours = [] } = data;
  const [filter, setFilter] = useState('');
  const [sortKey, setSortKey] = useState<SortKey>('ms');
  const needle = filter.toLowerCase();
  const rows = behaviours
    .filter(
      (b) =>
        !needle ||
        b.name.toLowerCase().includes(needle) ||
        b.lane.toLowerCase().includes(needle),
    )
    .sort((a, b) => b[sortKey] - a[sortKey]);
  const sortButton = (key: SortKey, label: string) => (
    <Button selected={sortKey === key} onClick={() => setSortKey(key)}>
      {label}
    </Button>
  );
  return (
    <Section
      buttons={
        <>
          {sortButton('ms', 'Total')}
          {sortButton('runs', 'Runs')}
          {sortButton('us_per_run', 'Per run')}
          {sortButton('errors', 'Errors')}
        </>
      }
    >
      <Input
        fluid
        placeholder="Filter by name or lane"
        value={filter}
        onChange={(value) => setFilter(value)}
      />
      <Table>
        <Table.Row header>
          <Table.Cell>Behaviour</Table.Cell>
          <Table.Cell>Lane</Table.Cell>
          <Table.Cell>Runs</Table.Cell>
          <Table.Cell>Total ms</Table.Cell>
          <Table.Cell>ms/s</Table.Cell>
          <Table.Cell>us/run</Table.Cell>
          <Table.Cell>Max call ms</Table.Cell>
          <Table.Cell>Late max</Table.Cell>
          <Table.Cell>Defer</Table.Cell>
          <Table.Cell>Breach</Table.Cell>
          <Table.Cell>Err</Table.Cell>
          <Table.Cell>On ring</Table.Cell>
          <Table.Cell>Parked</Table.Cell>
        </Table.Row>
        {rows.map((b) => (
          <Table.Row key={b.type}>
            <Table.Cell>{b.name}</Table.Cell>
            <Table.Cell>{b.lane}</Table.Cell>
            <Table.Cell>{b.runs}</Table.Cell>
            <Table.Cell>{b.ms}</Table.Cell>
            <Table.Cell>{b.ms_per_s}</Table.Cell>
            <Table.Cell>{b.us_per_run}</Table.Cell>
            <Table.Cell>{b.call_max_ms}</Table.Cell>
            <Table.Cell>{b.late_max}</Table.Cell>
            <Table.Cell>{b.deferrals}</Table.Cell>
            <Table.Cell>{b.breaches}</Table.Cell>
            <Table.Cell color={b.errors ? 'bad' : undefined}>
              {b.errors}
            </Table.Cell>
            <Table.Cell>{b.population}</Table.Cell>
            <Table.Cell>{b.parked}</Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

const StagesTab = (props) => {
  const { data } = useBackend<Data>();
  const { stages = [] } = data;
  const rows = [...stages].sort((a, b) => b.ms - a.ms);
  if (!rows.length) {
    return (
      <NoticeBox>
        No stage timings. A pipeline records them when its profile_stride is set
        (every Nth frame is timed per stage).
      </NoticeBox>
    );
  }
  return (
    <Section>
      <Table>
        <Table.Row header>
          <Table.Cell>Stage / entity type</Table.Cell>
          <Table.Cell>Calls</Table.Cell>
          <Table.Cell>Total ms</Table.Cell>
          <Table.Cell>us/call</Table.Cell>
        </Table.Row>
        {rows.map((s) => (
          <Table.Row key={s.key}>
            <Table.Cell>{s.key}</Table.Cell>
            <Table.Cell>{s.calls}</Table.Cell>
            <Table.Cell>{s.ms}</Table.Cell>
            <Table.Cell>{s.us_per_call}</Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

const ServicesTab = (props) => {
  const { data } = useBackend<Data>();
  const { services = [], world_step } = data;
  const rows = [...services].sort((a, b) => b.ms - a.ms);
  return (
    <>
      {world_step && (
        <Section title="World step (Rust scheduler)">
          <LabeledList>
            <LabeledList.Item label="Last step">
              {world_step.step_ms} ms
            </LabeledList.Item>
            <LabeledList.Item label="Wakes (last / total)">
              {world_step.last_wakes} / {world_step.total_wakes}
            </LabeledList.Item>
            <LabeledList.Item label="Dropped">
              {world_step.dropped}
            </LabeledList.Item>
          </LabeledList>
        </Section>
      )}
      <Section title="World services (totals since boot)">
        <Table>
          <Table.Row header>
            <Table.Cell>Service</Table.Cell>
            <Table.Cell>State</Table.Cell>
            <Table.Cell>Steps</Table.Cell>
            <Table.Cell>Total ms</Table.Cell>
            <Table.Cell>ms/s</Table.Cell>
            <Table.Cell>Avg step ms</Table.Cell>
            <Table.Cell>Status</Table.Cell>
          </Table.Row>
          {rows.map((s) => (
            <Table.Row key={s.type}>
              <Table.Cell>{s.name}</Table.Cell>
              <Table.Cell>
                {!s.initialized
                  ? 'not initialized'
                  : s.parked
                    ? 'parked'
                    : s.resuming
                      ? 'resuming'
                      : s.on_demand
                        ? 'on demand'
                        : 'running'}
              </Table.Cell>
              <Table.Cell>{s.steps}</Table.Cell>
              <Table.Cell>{s.ms}</Table.Cell>
              <Table.Cell>{s.ms_per_s}</Table.Cell>
              <Table.Cell>{s.avg_ms}</Table.Cell>
              <Table.Cell>{s.status}</Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
    </>
  );
};

const CachesTab = (props) => {
  const { data } = useBackend<Data>();
  const caches = [...(data.caches || [])].sort((a, b) => b.kb - a.kb);
  return (
    <Section title="Shared caches (DECLARE_SHARED_CACHE; hits need -DSHARED_CACHE_STATS in release)">
      <Table>
        <Table.Row header>
          <Table.Cell>Cache</Table.Cell>
          <Table.Cell>Policy</Table.Cell>
          <Table.Cell textAlign="right">Hits</Table.Cell>
          <Table.Cell textAlign="right">Misses</Table.Cell>
          <Table.Cell textAlign="right">Hit %</Table.Cell>
          <Table.Cell textAlign="right">Entries</Table.Cell>
          <Table.Cell textAlign="right">Evicted</Table.Cell>
          <Table.Cell textAlign="right">Cleared</Table.Cell>
          <Table.Cell textAlign="right">~KB</Table.Cell>
        </Table.Row>
        {caches.map((c) => (
          <Table.Row key={c.name}>
            <Table.Cell>{c.name}</Table.Cell>
            <Table.Cell>{c.policy}</Table.Cell>
            <Table.Cell textAlign="right">{c.hits ?? '-'}</Table.Cell>
            <Table.Cell textAlign="right">{c.misses}</Table.Cell>
            <Table.Cell textAlign="right">
              {c.hits === null ? '-' : c.hit_rate}
            </Table.Cell>
            <Table.Cell textAlign="right">
              {c.entries}
              {c.max_entries ? ` / ${c.max_entries}` : ''}
            </Table.Cell>
            <Table.Cell textAlign="right">{c.evictions}</Table.Cell>
            <Table.Cell textAlign="right">{c.invalidations}</Table.Cell>
            <Table.Cell textAlign="right">{c.kb}</Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};
