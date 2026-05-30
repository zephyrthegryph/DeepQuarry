// Exosuit main interface — TGUI.
//
// Five fully-structured views in one window, switched by `view`:
//   main       — stats + commands + equipment + eject
//   log        — internal log entries
//   attack_ai  — AI attack interface (equipment select to fire on target)
//   access     — ID access add/remove keycode dialog
//   maint      — maintenance console actions

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  ProgressBar,
  Section,
  Stack,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type DamageReport = {
  key: string;
  label: string;
  has_repair: BooleanLike;
};

type Cargo = {
  ref: string;
  name: string;
};

type EquipPiece = {
  ref: string;
  name: string;
  kind: string;
  info_lines: string[];
};

type EquipSlotInfo = {
  label: string;
  used: number;
  max: number;
};

type LogEntry = {
  time: string;
  message: string;
};

type AccessKey = {
  id: number;
  name: string;
};

type Data = {
  view: 'main' | 'log' | 'attack_ai' | 'access' | 'maint';
  title: string;
  // main view
  damage_reports: DamageReport[];
  high_pressure: BooleanLike;
  has_armor: BooleanLike;
  armor_percent: number;
  has_hull: BooleanLike;
  hull_percent: number;
  integrity_percent: number;
  cell_percent: number | null;
  use_internal_tank: BooleanLike;
  tank_pressure: number | string;
  tank_temp_k: number | string;
  tank_temp_c: number | string;
  cabin_pressure: number;
  cabin_temp_k: number;
  cabin_temp_c: number;
  lights: BooleanLike;
  dna_lock: string;
  defence_mode_possible: BooleanLike;
  defence_mode: BooleanLike;
  overload_possible: BooleanLike;
  overload: BooleanLike;
  smoke_possible: BooleanLike;
  smoke_reserve: number;
  thrusters_possible: BooleanLike;
  thrusters: BooleanLike;
  cargo: Cargo[];
  radio_mic: BooleanLike;
  radio_spk: BooleanLike;
  radio_freq: string;
  airtank_disconnect: BooleanLike;
  airtank_connect: BooleanLike;
  id_upload_locked: BooleanLike;
  maint_access: BooleanLike;
  equipment: EquipPiece[];
  slots: EquipSlotInfo[];
  can_eject: BooleanLike;
  // log view
  log_entries: LogEntry[];
  // attack_ai view
  ai_targets: EquipPiece[];
  ai_target_name: string;
  // access view
  access_current: AccessKey[];
  access_available: AccessKey[];
  // maint view
  maint_can_req_access: BooleanLike;
  maint_can_maint_access: BooleanLike;
  maint_can_set_air: BooleanLike;
  maint_can_remove_passenger: BooleanLike;
};

export const MechaInterface = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Window width={680} height={780} title={data.title}>
      <Window.Content scrollable>
        {data.view !== 'main' ? (
          <Section>
            <Button icon="arrow-left" onClick={() => act('view_main')}>
              Back to main view
            </Button>
          </Section>
        ) : null}
        {data.view === 'main' && <MainView />}
        {data.view === 'log' && <LogView />}
        {data.view === 'attack_ai' && <AttackAiView />}
        {data.view === 'access' && <AccessView />}
        {data.view === 'maint' && <MaintView />}
      </Window.Content>
    </Window>
  );
};

const MainView = () => {
  const { data, act } = useBackend<Data>();
  return (
    <>
      <DamageBanner />
      <StatsPanel />
      <CommandsPanel />
      <EquipmentPanel />
      {data.can_eject ? (
        <Section>
          <Button
            fluid
            icon="sign-out-alt"
            color="bad"
            onClick={() => act('eject')}
          >
            Eject
          </Button>
        </Section>
      ) : null}
    </>
  );
};

const DamageBanner = () => {
  const { data, act } = useBackend<Data>();
  const { damage_reports, high_pressure } = data;
  if (damage_reports.length === 0 && !high_pressure) return null;
  return (
    <Section>
      {damage_reports.map((d) => (
        <Box key={d.key} color="bad" bold>
          {d.label}
          {d.has_repair ? (
            <>
              {' — '}
              <Button onClick={() => act(d.key)}>Recalibrate</Button>
            </>
          ) : null}
        </Box>
      ))}
      {high_pressure ? (
        <Box color="bad" bold>
          DANGEROUSLY HIGH CABIN PRESSURE
        </Box>
      ) : null}
    </Section>
  );
};

const integrityColor = (pct: number) =>
  pct < 30 ? 'bad' : pct < 70 ? 'average' : 'good';

const StatsPanel = () => {
  const { data, act } = useBackend<Data>();
  const {
    has_armor,
    armor_percent,
    has_hull,
    hull_percent,
    integrity_percent,
    cell_percent,
    use_internal_tank,
    tank_pressure,
    tank_temp_k,
    tank_temp_c,
    cabin_pressure,
    cabin_temp_k,
    cabin_temp_c,
    lights,
    dna_lock,
    defence_mode_possible,
    defence_mode,
    overload_possible,
    overload,
    smoke_possible,
    smoke_reserve,
    thrusters_possible,
    thrusters,
    cargo,
  } = data;
  return (
    <Section title="Status">
      <LabeledList>
        <LabeledList.Item label="Armor">
          {has_armor ? (
            <Box color={integrityColor(armor_percent)}>{armor_percent}%</Box>
          ) : (
            <Box color="bad">ARMOR MISSING</Box>
          )}
        </LabeledList.Item>
        <LabeledList.Item label="Hull">
          {has_hull ? (
            <Box color={integrityColor(hull_percent)}>{hull_percent}%</Box>
          ) : (
            <Box color="bad">HULL MISSING</Box>
          )}
        </LabeledList.Item>
        <LabeledList.Item label="Chassis">
          <ProgressBar
            value={integrity_percent}
            minValue={0}
            maxValue={100}
            ranges={{
              bad: [-Infinity, 30],
              average: [30, 70],
              good: [70, Infinity],
            }}
          >
            {integrity_percent}%
          </ProgressBar>
        </LabeledList.Item>
        <LabeledList.Item label="Powercell">
          {cell_percent === null ? (
            <Box color="bad">No powercell installed</Box>
          ) : (
            <ProgressBar
              value={cell_percent}
              minValue={0}
              maxValue={100}
              ranges={{
                bad: [-Infinity, 20],
                average: [20, 60],
                good: [60, Infinity],
              }}
            >
              {cell_percent}%
            </ProgressBar>
          )}
        </LabeledList.Item>
        <LabeledList.Item label="Air source">
          {use_internal_tank ? 'Internal Airtank' : 'Environment'}
        </LabeledList.Item>
        <LabeledList.Item label="Airtank">
          {tank_pressure} kPa, {tank_temp_k} K ({tank_temp_c}°C)
        </LabeledList.Item>
        <LabeledList.Item label="Cabin">
          {cabin_pressure} kPa, {cabin_temp_k} K ({cabin_temp_c}°C)
        </LabeledList.Item>
        <LabeledList.Item label="Lights">
          {lights ? 'on' : 'off'}
        </LabeledList.Item>
        {dna_lock ? (
          <LabeledList.Item label="DNA lock">
            <Box inline style={{ fontSize: '10px' }}>
              {dna_lock}
            </Box>{' '}
            <Button onClick={() => act('reset_dna')}>Reset</Button>
          </LabeledList.Item>
        ) : null}
        {defence_mode_possible ? (
          <LabeledList.Item label="Defence mode">
            {defence_mode ? 'on' : 'off'}
          </LabeledList.Item>
        ) : null}
        {overload_possible ? (
          <LabeledList.Item label="Overload">
            {overload ? 'on' : 'off'}
          </LabeledList.Item>
        ) : null}
        {smoke_possible ? (
          <LabeledList.Item label="Smoke">{smoke_reserve}</LabeledList.Item>
        ) : null}
        {thrusters_possible ? (
          <LabeledList.Item label="Thrusters">
            {thrusters ? 'on' : 'off'}
          </LabeledList.Item>
        ) : null}
      </LabeledList>
      <Section title="Cargo" mt={1}>
        {cargo.length === 0 ? (
          <EmptyState>Nothing</EmptyState>
        ) : (
          <Stack vertical>
            {cargo.map((c) => (
              <Stack.Item key={c.ref}>
                <Button onClick={() => act('drop_from_cargo', { ref: c.ref })}>
                  Unload
                </Button>{' '}
                {c.name}
              </Stack.Item>
            ))}
          </Stack>
        )}
      </Section>
    </Section>
  );
};

const CommandsPanel = () => {
  const { data, act } = useBackend<Data>();
  const {
    lights,
    radio_mic,
    radio_spk,
    radio_freq,
    airtank_disconnect,
    airtank_connect,
    id_upload_locked,
    maint_access,
  } = data;
  return (
    <>
      <Section title="Electronics">
        <LabeledList>
          <LabeledList.Item label="Lights">
            <Button selected={!!lights} onClick={() => act('toggle_lights')}>
              {lights ? 'On' : 'Off'}
            </Button>
          </LabeledList.Item>
          <LabeledList.Item label="Radio Mic">
            <Button selected={!!radio_mic} onClick={() => act('rmictoggle')}>
              {radio_mic ? 'Engaged' : 'Disengaged'}
            </Button>
          </LabeledList.Item>
          <LabeledList.Item label="Radio Speaker">
            <Button selected={!!radio_spk} onClick={() => act('rspktoggle')}>
              {radio_spk ? 'Engaged' : 'Disengaged'}
            </Button>
          </LabeledList.Item>
          <LabeledList.Item label="Frequency">
            <Button onClick={() => act('rfreq', { delta: -10 })}>-10</Button>{' '}
            <Button onClick={() => act('rfreq', { delta: -2 })}>-2</Button>{' '}
            <Box inline bold mx={1}>
              {radio_freq}
            </Box>
            <Button onClick={() => act('rfreq', { delta: 2 })}>+2</Button>{' '}
            <Button onClick={() => act('rfreq', { delta: 10 })}>+10</Button>
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section title="Airtank">
        <Button onClick={() => act('toggle_airtank')}>
          Toggle Internal Airtank
        </Button>{' '}
        {airtank_disconnect ? (
          <Button onClick={() => act('port_disconnect')}>
            Disconnect from port
          </Button>
        ) : null}{' '}
        {airtank_connect ? (
          <Button onClick={() => act('port_connect')}>Connect to port</Button>
        ) : null}
      </Section>
      <Section title="Permissions & Logging">
        <Button onClick={() => act('toggle_id_upload')}>
          {id_upload_locked ? 'Lock' : 'Unlock'} ID upload panel
        </Button>{' '}
        <Button onClick={() => act('toggle_maint_access')}>
          {maint_access ? 'Forbid' : 'Permit'} maintenance protocols
        </Button>{' '}
        <Button onClick={() => act('dna_lock')}>DNA-lock</Button>{' '}
        <Button onClick={() => act('view_log')}>View internal log</Button>{' '}
        <Button onClick={() => act('change_name')}>Change exosuit name</Button>
      </Section>
    </>
  );
};

const EquipmentPanel = () => {
  const { data, act } = useBackend<Data>();
  const { equipment, slots } = data;
  return (
    <Section title="Equipment">
      {equipment.length === 0 ? (
        <EmptyState>No equipment attached.</EmptyState>
      ) : (
        <Stack vertical>
          {equipment.map((e) => (
            <Stack.Item key={e.ref}>
              <Section
                title={`${e.kind}: ${e.name}`}
                buttons={
                  <>
                    <Button
                      onClick={() => act('equip_interact', { ref: e.ref })}
                    >
                      Open
                    </Button>{' '}
                    <Button
                      color="bad"
                      onClick={() => act('detach_equipment', { ref: e.ref })}
                    >
                      Detach
                    </Button>
                  </>
                }
              >
                {e.info_lines.map((line, i) => (
                  <Box key={i} color="label">
                    {line}
                  </Box>
                ))}
              </Section>
            </Stack.Item>
          ))}
        </Stack>
      )}
      <Box mt={1}>
        {slots.map((s) => (
          <Box key={s.label}>
            <Box inline bold>
              {s.label}:
            </Box>{' '}
            {s.max - s.used} free ({s.used}/{s.max})
          </Box>
        ))}
      </Box>
    </Section>
  );
};

const LogView = () => {
  const { data } = useBackend<Data>();
  return (
    <Section title="Internal Log">
      {data.log_entries.length === 0 ? (
        <EmptyState>No entries.</EmptyState>
      ) : (
        <Stack vertical>
          {data.log_entries.map((e, i) => (
            <Stack.Item key={i}>
              <Box bold>{e.time}</Box>
              <Box ml={2}>{e.message}</Box>
            </Stack.Item>
          ))}
        </Stack>
      )}
    </Section>
  );
};

const AttackAiView = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Section title={`Attack: ${data.ai_target_name}`}>
      {data.ai_targets.length === 0 ? (
        <EmptyState>No equipment available for attack.</EmptyState>
      ) : (
        <Stack vertical>
          {data.ai_targets.map((eq) => (
            <Stack.Item key={eq.ref}>
              <Button
                fluid
                onClick={() => act('ai_use_equipment', { ref: eq.ref })}
              >
                {eq.kind}: {eq.name}
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      )}
    </Section>
  );
};

const AccessView = () => {
  const { data, act } = useBackend<Data>();
  return (
    <>
      <Section title="Operation Keycodes">
        {data.access_current.length === 0 ? (
          <EmptyState>No keycodes required.</EmptyState>
        ) : (
          <Stack vertical>
            {data.access_current.map((k) => (
              <Stack.Item key={k.id}>
                <Button
                  color="bad"
                  onClick={() => act('access_del', { id: k.id })}
                >
                  Delete
                </Button>{' '}
                {k.name}
              </Stack.Item>
            ))}
          </Stack>
        )}
      </Section>
      <Section title="Available on portable device">
        {data.access_available.length === 0 ? (
          <EmptyState>No additional keycodes available on card.</EmptyState>
        ) : (
          <Stack vertical>
            {data.access_available.map((k) => (
              <Stack.Item key={k.id}>
                <Button
                  color="good"
                  onClick={() => act('access_add', { id: k.id })}
                >
                  Add
                </Button>{' '}
                {k.name}
              </Stack.Item>
            ))}
          </Stack>
        )}
      </Section>
      <Section>
        <Button color="bad" onClick={() => act('access_finish')}>
          Finish (lock ID upload panel)
        </Button>
      </Section>
    </>
  );
};

const MaintView = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Section title="Maintenance Console">
      {data.maint_can_req_access ? (
        <Button fluid onClick={() => act('maint_req_access')}>
          Edit operation keycodes
        </Button>
      ) : null}
      {data.maint_can_maint_access ? (
        <Button fluid onClick={() => act('maint_protocol')}>
          Initiate maintenance protocol
        </Button>
      ) : null}
      {data.maint_can_set_air ? (
        <Button fluid onClick={() => act('maint_set_air')}>
          Set Cabin Air Pressure
        </Button>
      ) : null}
      {data.maint_can_remove_passenger ? (
        <Button fluid onClick={() => act('maint_remove_passenger')}>
          Remove Passenger
        </Button>
      ) : null}
    </Section>
  );
};
