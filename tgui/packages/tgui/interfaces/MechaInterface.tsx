// Exosuit main interface — TGUI.
//
// Four fully-structured views in one window, switched by `view`:
//   main       — stats + commands + equipment + eject
//   log        — internal log entries
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
import { EmptyState } from './common/EmptyState';
import type {
  MechaInterfaceActions,
  MechaInterfaceData,
} from './generated/MechaInterface';
import { StatBar } from 'tgui/components/StatBar';
import { Label } from 'tgui/components/Label';
import { YesNo } from 'tgui/components/YesNo';

type Main = NonNullable<MechaInterfaceData['main']>;

export const MechaInterface = () => {
  const { data, act } = useBackend<MechaInterfaceData, MechaInterfaceActions>();
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
        {data.view === 'access' && <AccessView />}
        {data.view === 'maint' && <MaintView />}
      </Window.Content>
    </Window>
  );
};

const MainView = () => {
  const { data, act } = useBackend<MechaInterfaceData, MechaInterfaceActions>();
  const { main } = data;
  if (!main) {
    return null;
  }
  return (
    <>
      <DamageBanner main={main} />
      <StatsPanel main={main} />
      <CommandsPanel main={main} />
      <EquipmentPanel main={main} />
      {main.can_eject ? (
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

const DamageBanner = (props: { main: Main }) => {
  const { act } = useBackend<MechaInterfaceData, MechaInterfaceActions>();
  const { damage_reports, high_pressure, integrity_percent } = props.main;
  const critical = integrity_percent < 30;
  if (damage_reports.length === 0 && !high_pressure && !critical) return null;
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
      {critical ? (
        <Box color="bad" bold>
          DAMAGE LEVEL CRITICAL
        </Box>
      ) : null}
    </Section>
  );
};

const integrityColor = (pct: number) =>
  pct < 30 ? 'bad' : pct < 70 ? 'average' : 'good';

const StatsPanel = (props: { main: Main }) => {
  const { act } = useBackend<MechaInterfaceData, MechaInterfaceActions>();
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
  } = props.main;
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
        <StatBar
          label="Chassis"
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
        </StatBar>
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
          {tank_pressure === null
            ? 'None'
            : `${tank_pressure} kPa, ${tank_temp_k ?? 'Unknown'} K (${tank_temp_c ?? 'Unknown'}°C)`}
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
              <Stack.Item key={c.id}>
                <Button onClick={() => act('drop_from_cargo', { id: c.id })}>
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

const CommandsPanel = (props: { main: Main }) => {
  const { act } = useBackend<MechaInterfaceData, MechaInterfaceActions>();
  const {
    lights,
    radio_mic,
    radio_spk,
    radio_freq,
    airtank_disconnect,
    airtank_connect,
    id_upload_locked,
    maint_access,
    commands,
  } = props.main;
  return (
    <>
      {commands.length > 0 ? (
        <Section title="Special">
          <Stack vertical>
            {commands.map((c) => (
              <Stack.Item key={c.key}>
                <Button onClick={() => act(c.key)}>{c.label}</Button>
              </Stack.Item>
            ))}
          </Stack>
        </Section>
      ) : null}
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

const EquipmentPanel = (props: { main: Main }) => {
  const { act } = useBackend<MechaInterfaceData, MechaInterfaceActions>();
  const { equipment, slots } = props.main;
  return (
    <Section title="Equipment">
      {equipment.length === 0 ? (
        <EmptyState>No equipment attached.</EmptyState>
      ) : (
        <Stack vertical>
          {equipment.map((e) => (
            <Stack.Item key={e.id}>
              <Section
                title={`${e.kind}: ${e.name}`}
                buttons={
                  <>
                    <Button
                      selected={!!e.selected}
                      onClick={() => act('select_equip', { id: e.id })}
                    >
                      {e.selected ? 'Selected' : 'Select'}
                    </Button>{' '}
                    <Button
                      color="bad"
                      onClick={() => act('detach_equipment', { id: e.id })}
                    >
                      Detach
                    </Button>
                  </>
                }
              >
                <YesNo value={e.ready} yes="Ready" no="Not ready" />
                {e.info_lines.map((line, i) => (
                  <Label key={i}>{line}</Label>
                ))}
                {e.controls.length > 0 ? (
                  <Box mt={0.5}>
                    {e.controls.map((c) => (
                      <Button
                        key={`${c.key}-${c.value ?? ''}`}
                        onClick={() =>
                          act('equip_control', {
                            id: e.id,
                            control: c.key,
                            value: c.value ?? undefined,
                          })
                        }
                      >
                        {c.label}
                      </Button>
                    ))}
                  </Box>
                ) : null}
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
  const { data } = useBackend<MechaInterfaceData, MechaInterfaceActions>();
  const logEntries = data.log_entries ?? [];
  return (
    <Section title="Internal Log">
      {logEntries.length === 0 ? (
        <EmptyState>No entries.</EmptyState>
      ) : (
        <Stack vertical>
          {logEntries.map((e, i) => (
            <Stack.Item key={i}>
              <Box bold>
                ({e.time}) ({e.year})
              </Box>
              <Box ml={2}>{e.message}</Box>
            </Stack.Item>
          ))}
        </Stack>
      )}
    </Section>
  );
};

const AccessView = () => {
  const { data, act } = useBackend<MechaInterfaceData, MechaInterfaceActions>();
  const { access } = data;
  if (!access) {
    return null;
  }
  return (
    <>
      <Section title="Operation Keycodes">
        {access.current.length === 0 ? (
          <EmptyState>No keycodes required.</EmptyState>
        ) : (
          <Stack vertical>
            {access.current.map((k) => (
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
        {access.available.length === 0 ? (
          <EmptyState>No additional keycodes available on card.</EmptyState>
        ) : (
          <Stack vertical>
            {access.available.map((k) => (
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
  const { data, act } = useBackend<MechaInterfaceData, MechaInterfaceActions>();
  const { maint } = data;
  if (!maint) {
    return null;
  }
  return (
    <Section title="Maintenance Console">
      {maint.can_req_access ? (
        <Button fluid onClick={() => act('maint_req_access')}>
          Edit operation keycodes
        </Button>
      ) : null}
      {maint.can_maint_access ? (
        <Button fluid onClick={() => act('maint_protocol')}>
          Initiate maintenance protocol
        </Button>
      ) : null}
      {maint.can_set_air ? (
        <Button fluid onClick={() => act('maint_set_air')}>
          Set Cabin Air Pressure
        </Button>
      ) : null}
      {maint.can_remove_passenger ? (
        <Button fluid onClick={() => act('maint_remove_passenger')}>
          Remove Passenger
        </Button>
      ) : null}
    </Section>
  );
};
