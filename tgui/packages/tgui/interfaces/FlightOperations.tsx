import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { WebGLCelestialScene } from './FlightOperationsScene';
import type {
  FlightOperationsActions,
  FlightOperationsData,
} from './generated/FlightOperations';
import { Label } from 'tgui/components/Label';

type Kind =
  | 'system'
  | 'surface'
  | 'station'
  | 'vessel'
  | 'orbit'
  | 'expedition';

export type FlightDestination = {
  id: string;
  name: string;
  description: string;
  kind: Kind;
  scene_role?: 'celestial' | 'orbital' | 'docked';
  orbit_parent_id?: string | null;
  docked_port_id?: string | null;
  docked_host_id?: string | null;
  orbit_radius: number;
  orbit_period: number;
  orbit_phase: number;
  orbit_inclination: number;
  body_radius: number;
  body_color: string;
  latitude?: number | null;
  longitude?: number | null;
  compatible: BooleanLike;
  materialized: BooleanLike;
  is_current: BooleanLike;
};

export type FlightPlan = {
  id: string;
  origin_id?: string | null;
  destination_id: string | null;
  destination: string | null;
  state: number;
  state_name: string;
  failure?: string | null;
  eta: number;
  departure_at: number;
  arrival_at: number;
  generation_progress: number;
  generation_stage: string | null;
};

const labelFor = (kind: Kind) =>
  ({
    system: 'Star',
    surface: 'Planet',
    station: 'Station',
    vessel: 'Vessel',
    orbit: 'Orbital installation',
    expedition: 'Surface site',
  })[kind];

export const FlightOperations = () => {
  const { act, data } = useBackend<
    FlightOperationsData,
    FlightOperationsActions
  >();
  const destinations = data.destinations ?? [];
  const system = destinations.find((body) => body.kind === 'system');
  const [focusId, setFocusId] = useState('system-vir');
  const [selectedId, setSelectedId] = useState<string>();
  const focus = destinations.find((body) => body.id === focusId);
  const selected = destinations.find((body) => body.id === selectedId);

  return (
    <Window
      width={1040}
      height={680}
      title={`${data.vessel} — Flight Operations`}
    >
      <Window.Content>
        <Stack fill>
          <Stack.Item grow position="relative">
            <WebGLCelestialScene
              bodies={destinations}
              focusId={focusId}
              selectedId={selectedId}
              vesselDestinationId={data.vessel_destination_id}
              plan={data.plan}
              serverTime={data.server_time}
              onFocus={setFocusId}
              onSelect={setSelectedId}
            />
            <Box position="absolute" top="10px" left="12px">
              <Button
                icon="sun"
                selected={focus?.kind === 'system'}
                onClick={() => system && setFocusId(system.id)}
              >
                Vir system
              </Button>
              {focus?.kind === 'surface' && (
                <Button ml={1} icon="globe" selected>
                  {focus.name}
                </Button>
              )}
            </Box>
            <Label position="absolute" bottom="10px" left="12px">
              Left drag to orbit · right drag to pan · wheel to zoom · click
              planets to inspect
            </Label>
          </Stack.Item>
          <Stack.Item basis="335px">
            <Section title="Navigation" fill scrollable>
              <LabeledList>
                <LabeledList.Item label="Current vessel">
                  {data.vessel}
                </LabeledList.Item>
                <LabeledList.Item label="State">
                  {data.docked_port_id
                    ? 'Docked'
                    : data.plan
                      ? data.plan.state_name
                      : 'In orbit'}
                </LabeledList.Item>
              </LabeledList>
              {selected ? (
                <Section mt={2} title={selected.name}>
                  <Label>{labelFor(selected.kind)}</Label>
                  <Box mt={1}>{selected.description}</Box>
                  {selected.kind === 'expedition' && (
                    <Box mt={1}>
                      <LabeledList>
                        <LabeledList.Item label="Latitude">
                          {selected.latitude?.toFixed(2)}°
                        </LabeledList.Item>
                        <LabeledList.Item label="Longitude">
                          {selected.longitude?.toFixed(2)}°
                        </LabeledList.Item>
                      </LabeledList>
                    </Box>
                  )}
                  {selected.kind !== 'system' && !selected.is_current && (
                    <Button
                      mt={2}
                      fluid
                      color="good"
                      icon="rocket"
                      disabled={
                        !selected.compatible ||
                        (!!data.plan && data.plan.state !== 1)
                      }
                      onClick={() =>
                        act('jump', { destination_id: selected.id })
                      }
                    >
                      Initiate Jump
                    </Button>
                  )}
                </Section>
              ) : (
                <Label mt={2}>
                  Select a planet, station, vessel, or surface site.
                </Label>
              )}
              {data.plan && (
                <Section mt={2} title="Active Jump">
                  <LabeledList>
                    <LabeledList.Item label="Destination">
                      {data.plan.destination}
                    </LabeledList.Item>
                    <LabeledList.Item label="State">
                      {data.plan.state_name}
                    </LabeledList.Item>
                    <LabeledList.Item label="ETA">
                      {(data.plan.eta / 10).toFixed(1)} seconds
                    </LabeledList.Item>
                  </LabeledList>
                  {data.plan.failure && (
                    <Box color="bad">{data.plan.failure}</Box>
                  )}
                  <Button.Confirm
                    mt={1}
                    fluid
                    color="bad"
                    icon="ban"
                    onClick={() => act('abort')}
                  >
                    Abort Jump
                  </Button.Confirm>
                </Section>
              )}
              {data.expedition && (
                <Section mt={2} title="Surface Contract">
                  <Box bold>{data.expedition.name}</Box>
                  <Box mt={1}>{data.expedition.objective}</Box>
                  <Label>{data.expedition.progress}</Label>
                  {data.expedition.infrastructure && (
                    <Box mt={1} color="average">
                      {data.expedition.infrastructure}
                    </Box>
                  )}
                </Section>
              )}
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
