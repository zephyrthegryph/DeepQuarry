import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Data = {
  power: {
    main: number;
    main_timeleft: number;
    backup: number;
    backup_timeleft: number;
  };
  wires: {
    main_1: BooleanLike;
    main_2: BooleanLike;
    backup_1: BooleanLike;
    backup_2: BooleanLike;
    shock: BooleanLike;
    id_scanner: BooleanLike;
    bolts: BooleanLike;
    lights: BooleanLike;
    safe: BooleanLike;
    timing: BooleanLike;
  };
  electrified: BooleanLike;
  electrified_left: number;
  emergency: BooleanLike;
  id_scanner: BooleanLike;
  lights: BooleanLike;
  bolted: BooleanLike;
  safe: BooleanLike;
  speed: BooleanLike;
  opened: BooleanLike;
  welded: BooleanLike;
};

const dangerMap: Record<number, { color: string; localStatusText: string }> = {
  2: {
    color: 'good',
    localStatusText: 'Optimal',
  },
  1: {
    color: 'average',
    localStatusText: 'Caution',
  },
  0: {
    color: 'bad',
    localStatusText: 'Offline',
  },
};

export const AiAirlock = (props) => {
  const { act, data } = useBackend<Data>();
  const flat = data;

  const {
    power,
    wires,
    electrified,
    electrified_left,
    emergency,
    id_scanner,
    lights,
    bolted,
    safe,
    speed,
    opened,
    welded,
  } = flat;

  const statusMain = dangerMap[power?.main] || dangerMap[0];
  const statusBackup = dangerMap[power?.backup] || dangerMap[0];
  const shock = electrified ? 0 : 2;
  const statusElectrify = dangerMap[shock];
  return (
    <Window width={500} height={420}>
      <Window.Content>
        <Section title="Power Status">
          <LabeledList>
            <LabeledList.Item
              label="Main"
              color={statusMain.color}
              buttons={
                <Button
                  icon="lightbulb-o"
                  disabled={!power.main}
                  onClick={() => act('disrupt-main')}
                >
                  Disrupt
                </Button>
              }
            >
              {power.main ? 'Online' : 'Offline'}{' '}
              {((!wires.main_1 || !wires.main_2) && '[Wires have been cut!]') ||
                (power.main_timeleft > 0 && `[${power.main_timeleft}s]`)}
            </LabeledList.Item>
            <LabeledList.Item
              label="Backup"
              color={statusBackup.color}
              buttons={
                <Button
                  icon="lightbulb-o"
                  disabled={!power.backup}
                  onClick={() => act('disrupt-backup')}
                >
                  Disrupt
                </Button>
              }
            >
              {power.backup ? 'Online' : 'Offline'}{' '}
              {((!wires.backup_1 || !wires.backup_2) &&
                '[Wires have been cut!]') ||
                (power.backup_timeleft > 0 && `[${power.backup_timeleft}s]`)}
            </LabeledList.Item>
            <LabeledList.Item
              label="Electrify"
              color={statusElectrify.color}
              buttons={
                <Stack>
                  <Stack.Item>
                    <Button
                      icon="wrench"
                      disabled={!(wires.shock && shock === 0)}
                      onClick={() => act('shock-restore')}
                    >
                      Restore
                    </Button>
                  </Stack.Item>
                  <Stack.Item>
                    <Button
                      icon="bolt"
                      disabled={!wires.shock}
                      onClick={() => act('shock-temp')}
                    >
                      Temporary
                    </Button>
                  </Stack.Item>
                  <Stack.Item>
                    <Button
                      icon="bolt"
                      disabled={!wires.shock}
                      onClick={() => act('shock-perm')}
                    >
                      Permanent
                    </Button>
                  </Stack.Item>
                </Stack>
              }
            >
              {shock === 2 ? 'Safe' : 'Electrified'}{' '}
              {(!wires.shock && '[Wires have been cut!]') ||
                (electrified_left > 0 && `[${electrified_left}s]`) ||
                (electrified_left === -1 && '[Permanent]')}
            </LabeledList.Item>
          </LabeledList>
        </Section>
        <Section title="Access and Door Control">
          <LabeledList>
            <LabeledList.Item
              label="ID Scan"
              color="bad"
              buttons={
                <Button
                  icon={id_scanner ? 'power-off' : 'times'}
                  selected={id_scanner}
                  disabled={!wires.id_scanner}
                  onClick={() => act('idscan-toggle')}
                >
                  {id_scanner ? 'Enabled' : 'Disabled'}
                </Button>
              }
            >
              {!wires.id_scanner && '[Wires have been cut!]'}
            </LabeledList.Item>
            <LabeledList.Item
              label="Emergency Access"
              color="bad"
              buttons={
                <Button
                  icon={emergency ? 'power-off' : 'times'}
                  selected={emergency}
                  onClick={() => act('emergency-toggle')}
                >
                  {emergency ? 'Enabled' : 'Disabled'}
                </Button>
              }
            />
            <LabeledList.Divider />
            <LabeledList.Item
              label="Door Bolts"
              color="bad"
              buttons={
                <Button
                  icon={bolted ? 'lock' : 'unlock'}
                  selected={bolted}
                  disabled={!wires.bolts}
                  onClick={() => act('bolt-toggle')}
                >
                  {bolted ? 'Lowered' : 'Raised'}
                </Button>
              }
            >
              {!wires.bolts && '[Wires have been cut!]'}
            </LabeledList.Item>
            <LabeledList.Item
              label="Door Bolt Lights"
              color="bad"
              buttons={
                <Button
                  icon={lights ? 'power-off' : 'times'}
                  selected={lights}
                  disabled={!wires.lights}
                  onClick={() => act('light-toggle')}
                >
                  {lights ? 'Enabled' : 'Disabled'}
                </Button>
              }
            >
              {!wires.lights && '[Wires have been cut!]'}
            </LabeledList.Item>
            <LabeledList.Item
              label="Door Force Sensors"
              color="bad"
              buttons={
                <Button
                  icon={safe ? 'power-off' : 'times'}
                  selected={safe}
                  disabled={!wires.safe}
                  onClick={() => act('safe-toggle')}
                >
                  {safe ? 'Enabled' : 'Disabled'}
                </Button>
              }
            >
              {!wires.safe && '[Wires have been cut!]'}
            </LabeledList.Item>
            <LabeledList.Item
              label="Door Timing Safety"
              color="bad"
              buttons={
                <Button
                  icon={speed ? 'power-off' : 'times'}
                  selected={speed}
                  disabled={!wires.timing}
                  onClick={() => act('speed-toggle')}
                >
                  {speed ? 'Enabled' : 'Disabled'}
                </Button>
              }
            >
              {!wires.timing && '[Wires have been cut!]'}
            </LabeledList.Item>
            <LabeledList.Divider />
            <LabeledList.Item
              label="Door Control"
              color="bad"
              buttons={
                <Button
                  icon={opened ? 'sign-out-alt' : 'sign-in-alt'}
                  selected={opened}
                  disabled={bolted || welded}
                  onClick={() => act('open-close')}
                >
                  {opened ? 'Open' : 'Closed'}
                </Button>
              }
            >
              {!!(bolted || welded) && (
                <span>
                  [Door is {bolted ? 'bolted' : ''}
                  {bolted && welded ? ' and ' : ''}
                  {welded ? 'welded' : ''}!]
                </span>
              )}
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
