// Mounted-mecha sleeper — TGUI.
//
// Shows occupant vital stats, reagents in bloodstream, and a list of
// reagents available to inject from a connected syringe gun. Eject
// releases the occupant.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Reagent = {
  name: string;
  volume: number;
};

type Injectable = {
  ref: string;
  source_ref: string;
  name: string;
};

type Data = {
  has_occupant: number;
  occupant_name: string;
  status: string;
  health_percent: number;
  brute: number;
  oxy: number;
  tox: number;
  fire: number;
  body_temp_c: number;
  body_temp_f: number;
  reagents: Reagent[];
  injectables: Injectable[];
};

const goodIf = (cond: boolean) => (cond ? 'good' : 'bad');

export const MechaSleeper = () => {
  const { data, act } = useBackend<Data>();
  const {
    has_occupant,
    occupant_name,
    status,
    health_percent,
    brute,
    oxy,
    tox,
    fire,
    body_temp_c,
    body_temp_f,
    reagents,
    injectables,
  } = data;

  if (!has_occupant) {
    return (
      <Window width={420} height={220} title="Mounted Sleeper">
        <Window.Content>
          <Section>
            <EmptyState>The sleeper is empty.</EmptyState>
          </Section>
        </Window.Content>
      </Window>
    );
  }

  return (
    <Window width={440} height={520} title={`${occupant_name} statistics`}>
      <Window.Content scrollable>
        <Section
          title="Health"
          buttons={
            <Button icon="eject" color="bad" onClick={() => act('eject')}>
              Eject
            </Button>
          }
        >
          <LabeledList>
            <LabeledList.Item label="Status">
              <Box color={goodIf(status === 'Conscious')}>{status}</Box>
            </LabeledList.Item>
            <LabeledList.Item label="Health">
              <Box color={goodIf(health_percent > 50)}>{health_percent}%</Box>
            </LabeledList.Item>
            <LabeledList.Item label="Core Temp">
              <Box color={goodIf(body_temp_c > -23)}>
                {body_temp_c}°C / {body_temp_f}°F
              </Box>
            </LabeledList.Item>
            <LabeledList.Item label="Brute">
              <Box color={goodIf(brute < 60)}>{brute}%</Box>
            </LabeledList.Item>
            <LabeledList.Item label="Respiratory">
              <Box color={goodIf(oxy < 60)}>{oxy}%</Box>
            </LabeledList.Item>
            <LabeledList.Item label="Toxin">
              <Box color={goodIf(tox < 60)}>{tox}%</Box>
            </LabeledList.Item>
            <LabeledList.Item label="Burn">
              <Box color={goodIf(fire < 60)}>{fire}%</Box>
            </LabeledList.Item>
          </LabeledList>
        </Section>

        <Section title="Reagents in bloodstream">
          {reagents.length === 0 ? (
            <EmptyState>None.</EmptyState>
          ) : (
            <Stack vertical>
              {reagents.map((r) => (
                <Stack.Item key={r.name}>
                  <Box inline bold>
                    {r.name}
                  </Box>
                  : {r.volume}
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>

        <Section title="Inject from connected syringe gun">
          {injectables.length === 0 ? (
            <EmptyState>No syringe gun loaded with reagents.</EmptyState>
          ) : (
            <Stack vertical>
              {injectables.map((i) => (
                <Stack.Item key={i.ref}>
                  <Button
                    fluid
                    icon="syringe"
                    onClick={() =>
                      act('inject', {
                        ref: i.ref,
                        source: i.source_ref,
                      })
                    }
                  >
                    Inject {i.name}
                  </Button>
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
