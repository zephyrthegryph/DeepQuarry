import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
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
};

type Lane = {
  name: string;
  share: number;
  behaviours: number;
  runs: number;
  ms: number;
  ms_per_s: number;
};

type Stage = {
  key: string;
  calls: number;
  ms: number;
  us_per_call: number;
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
        </Tabs>
        {tab === 0 && <LanesTab />}
        {tab === 1 && <BehavioursTab />}
        {tab === 2 && <StagesTab />}
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
        </Table.Row>
        {lanes.map((lane) => (
          <Table.Row key={lane.name}>
            <Table.Cell>{lane.name}</Table.Cell>
            <Table.Cell>{Math.round(lane.share * 100)}%</Table.Cell>
            <Table.Cell>{lane.behaviours}</Table.Cell>
            <Table.Cell>{lane.runs}</Table.Cell>
            <Table.Cell>{lane.ms}</Table.Cell>
            <Table.Cell>{lane.ms_per_s}</Table.Cell>
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
        </Table.Row>
        {rows.map((b) => (
          <Table.Row key={b.type}>
            <Table.Cell>
              <Box title={b.type}>{b.name}</Box>
            </Table.Cell>
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
        No stage timings. A pipeline records them when its profile_stride is
        set (every Nth frame is timed per stage).
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
