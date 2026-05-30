// Event Manager admin panel — structured TGUI.
//
// Two views: the per-severity overview (timers, queued/running events)
// and the per-container "available events" detail view. The DM side
// picks which one based on whether `selected_severity` is set.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type SeverityRow = {
  ref: string;
  severity: string;
  starts_at: string;
  starts_in_minutes: number;
  delayed: BooleanLike;
  delay_modifier: number;
};

type NextEventRow = {
  ref: string;
  severity: string;
  queued_name: string | null;
};

type RunningEvent = {
  ref: string;
  severity: string;
  name: string;
  ends_at: string;
  ends_in_minutes: number;
};

type AvailableEvent = {
  ref: string;
  name: string;
  weight: number;
  min_weight: number;
  max_weight: number;
  one_shot: BooleanLike;
  enabled: BooleanLike;
  current_weight: number;
};

type NewEvent = {
  ref: string;
  name: string | null;
  type: string | null;
  weight: number;
  one_shot: BooleanLike;
};

type Data = {
  events_paused: BooleanLike;
  report_at_round_end: BooleanLike;
  selected_severity: string | null;
  // Overview-mode fields
  severities?: SeverityRow[];
  next_events?: NextEventRow[];
  running_events?: RunningEvent[];
  // Detail-mode fields
  selected_time_left_minutes?: number;
  selected_container_ref?: string;
  available_events?: AvailableEvent[];
  new_event?: NewEvent;
};

export const EventManagerPanel = () => {
  const { data, act } = useBackend<Data>();
  if (data.selected_severity) {
    return <DetailView data={data} act={act} />;
  }
  return <OverviewView data={data} act={act} />;
};

const HeaderButtons = (props: {
  data: Data;
  act: (action: string, params?: Record<string, unknown>) => void;
}) => {
  const { data, act } = props;
  return (
    <>
      <Button
        icon={data.events_paused ? 'play' : 'pause'}
        selected={!!data.events_paused}
        onClick={() => act('pause_all')}
      >
        {data.events_paused ? 'Resume all' : 'Pause all'}
      </Button>{' '}
      <Button
        selected={!!data.report_at_round_end}
        onClick={() => act('toggle_report')}
      >
        Round-end report: {data.report_at_round_end ? 'on' : 'off'}
      </Button>
    </>
  );
};

const OverviewView = (props: {
  data: Data;
  act: (action: string, params?: Record<string, unknown>) => void;
}) => {
  const { data, act } = props;
  const severities = data.severities ?? [];
  const next_events = data.next_events ?? [];
  const running = data.running_events ?? [];
  return (
    <Window width={760} height={620} title="Event Manager">
      <Window.Content scrollable>
        <Section
          title="Event Manager"
          buttons={<HeaderButtons data={data} act={act} />}
        >
          <Box color="label" mb={1}>
            Configure when events fire, queue the next event per severity, or
            stop a running event.
          </Box>
        </Section>

        <Section title="Event Start">
          <Table>
            <Table.Row header>
              <Table.Cell>Severity</Table.Cell>
              <Table.Cell>Starts At</Table.Cell>
              <Table.Cell>Starts In (min)</Table.Cell>
              <Table.Cell>Adjust Start</Table.Cell>
              <Table.Cell>Pause</Table.Cell>
              <Table.Cell>Interval Mod</Table.Cell>
            </Table.Row>
            {severities.map((s) => (
              <Table.Row key={s.ref}>
                <Table.Cell>{s.severity}</Table.Cell>
                <Table.Cell>{s.starts_at}</Table.Cell>
                <Table.Cell>{s.starts_in_minutes}</Table.Cell>
                <Table.Cell>
                  <Button
                    compact
                    onClick={() => act('dec_timer', { amount: 2, ref: s.ref })}
                  >
                    −−
                  </Button>{' '}
                  <Button
                    compact
                    onClick={() => act('dec_timer', { amount: 1, ref: s.ref })}
                  >
                    −
                  </Button>{' '}
                  <Button
                    compact
                    onClick={() => act('inc_timer', { amount: 1, ref: s.ref })}
                  >
                    +
                  </Button>{' '}
                  <Button
                    compact
                    onClick={() => act('inc_timer', { amount: 2, ref: s.ref })}
                  >
                    ++
                  </Button>
                </Table.Cell>
                <Table.Cell>
                  <Button
                    compact
                    selected={!!s.delayed}
                    onClick={() => act('toggle_pause', { ref: s.ref })}
                  >
                    {s.delayed ? 'Resume' : 'Pause'}
                  </Button>
                </Table.Cell>
                <Table.Cell>
                  <Button
                    compact
                    onClick={() => act('set_interval', { ref: s.ref })}
                  >
                    {s.delay_modifier}
                  </Button>
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>

        <Section title="Next Event">
          <Table>
            <Table.Row header>
              <Table.Cell>Severity</Table.Cell>
              <Table.Cell>Name</Table.Cell>
              <Table.Cell>Rotation</Table.Cell>
              <Table.Cell>Clear</Table.Cell>
            </Table.Row>
            {next_events.map((n) => (
              <Table.Row key={n.ref}>
                <Table.Cell>{n.severity}</Table.Cell>
                <Table.Cell>
                  <Button
                    compact
                    onClick={() => act('select_event', { ref: n.ref })}
                  >
                    {n.queued_name ?? 'Random'}
                  </Button>
                </Table.Cell>
                <Table.Cell>
                  <Button
                    compact
                    onClick={() => act('view_events', { ref: n.ref })}
                  >
                    View
                  </Button>
                </Table.Cell>
                <Table.Cell>
                  {n.queued_name ? (
                    <Button
                      compact
                      color="bad"
                      onClick={() => act('clear_event', { ref: n.ref })}
                    >
                      Clear
                    </Button>
                  ) : null}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>

        <Section title="Running Events">
          {running.length === 0 ? (
            <EmptyState>No events currently running.</EmptyState>
          ) : (
            <Table>
              <Table.Row header>
                <Table.Cell>Severity</Table.Cell>
                <Table.Cell>Name</Table.Cell>
                <Table.Cell>Ends At</Table.Cell>
                <Table.Cell>Ends In (min)</Table.Cell>
                <Table.Cell>Stop</Table.Cell>
              </Table.Row>
              {running.map((r) => (
                <Table.Row key={r.ref}>
                  <Table.Cell>{r.severity}</Table.Cell>
                  <Table.Cell>{r.name}</Table.Cell>
                  <Table.Cell>{r.ends_at}</Table.Cell>
                  <Table.Cell>{r.ends_in_minutes}</Table.Cell>
                  <Table.Cell>
                    <Button
                      compact
                      color="bad"
                      onClick={() => act('stop_event', { ref: r.ref })}
                    >
                      Stop
                    </Button>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};

const DetailView = (props: {
  data: Data;
  act: (action: string, params?: Record<string, unknown>) => void;
}) => {
  const { data, act } = props;
  const events = data.available_events ?? [];
  const new_event = data.new_event;
  const container_ref = data.selected_container_ref ?? '';
  return (
    <Window
      width={820}
      height={620}
      title={`Event Manager — ${data.selected_severity}`}
    >
      <Window.Content scrollable>
        <Section
          title={`${data.selected_severity} Events`}
          buttons={
            <>
              <HeaderButtons data={data} act={act} />{' '}
              <Button icon="arrow-left" onClick={() => act('back')}>
                Back
              </Button>
            </>
          }
        >
          <Box color="label" mb={1}>
            Time till next event in this severity:{' '}
            {data.selected_time_left_minutes} min
          </Box>
          {events.length === 0 ? (
            <EmptyState>No events configured at this severity.</EmptyState>
          ) : (
            <Table>
              <Table.Row header>
                <Table.Cell>Name</Table.Cell>
                <Table.Cell>Weight</Table.Cell>
                <Table.Cell>Min</Table.Cell>
                <Table.Cell>Max</Table.Cell>
                <Table.Cell>OneShot</Table.Cell>
                <Table.Cell>Enabled</Table.Cell>
                <Table.Cell>Current Weight</Table.Cell>
                <Table.Cell>Remove</Table.Cell>
              </Table.Row>
              {events.map((e) => (
                <Table.Row key={e.ref}>
                  <Table.Cell>{e.name}</Table.Cell>
                  <Table.Cell>
                    <Button
                      compact
                      onClick={() => act('set_weight', { ref: e.ref })}
                    >
                      {e.weight}
                    </Button>
                  </Table.Cell>
                  <Table.Cell>{e.min_weight}</Table.Cell>
                  <Table.Cell>{e.max_weight}</Table.Cell>
                  <Table.Cell>
                    <Button
                      compact
                      selected={!!e.one_shot}
                      onClick={() => act('toggle_oneshot', { ref: e.ref })}
                    >
                      {e.one_shot ? 'Yes' : 'No'}
                    </Button>
                  </Table.Cell>
                  <Table.Cell>
                    <Button
                      compact
                      selected={!!e.enabled}
                      onClick={() => act('toggle_enabled', { ref: e.ref })}
                    >
                      {e.enabled ? 'Yes' : 'No'}
                    </Button>
                  </Table.Cell>
                  <Table.Cell color="bad">{e.current_weight}</Table.Cell>
                  <Table.Cell>
                    <Button
                      compact
                      color="bad"
                      icon="trash"
                      onClick={() =>
                        act('remove_event', {
                          ref: e.ref,
                          container_ref,
                        })
                      }
                    >
                      Remove
                    </Button>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>

        {new_event ? (
          <Section title="Add Event">
            <Stack>
              <Stack.Item color="label">Name</Stack.Item>
              <Stack.Item>
                <Button onClick={() => act('set_name', { ref: new_event.ref })}>
                  {new_event.name ?? 'Enter event name'}
                </Button>
              </Stack.Item>
              <Stack.Item color="label">Type</Stack.Item>
              <Stack.Item>
                <Button onClick={() => act('set_type', { ref: new_event.ref })}>
                  {new_event.type ?? 'Select type'}
                </Button>
              </Stack.Item>
              <Stack.Item color="label">Weight</Stack.Item>
              <Stack.Item>
                <Button
                  onClick={() => act('set_weight', { ref: new_event.ref })}
                >
                  {new_event.weight}
                </Button>
              </Stack.Item>
              <Stack.Item color="label">OneShot</Stack.Item>
              <Stack.Item>
                <Button
                  selected={!!new_event.one_shot}
                  onClick={() => act('toggle_oneshot', { ref: new_event.ref })}
                >
                  {new_event.one_shot ? 'Yes' : 'No'}
                </Button>
              </Stack.Item>
              <Stack.Item>
                <Button
                  color="good"
                  icon="plus"
                  disabled={!new_event.name || !new_event.type}
                  onClick={() => act('add_event', { container_ref })}
                >
                  Add
                </Button>
              </Stack.Item>
            </Stack>
          </Section>
        ) : null}
      </Window.Content>
    </Window>
  );
};
