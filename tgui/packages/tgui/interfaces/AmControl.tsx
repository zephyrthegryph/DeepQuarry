// Antimatter control unit — TGUI.
//
// Toggles injection, ejects fuel jar, steps injection strength, and
// reports core/shielding stability.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Data = {
  active: BooleanLike;
  stability: number;
  shielding: number;
  cores: number;
  core_efficiency: number;
  core_stability: number;
  stored_power: number;
  has_fuel: BooleanLike;
  fuel: number;
  fuel_max: number;
  fuel_injection: number;
};

export const AmControl = () => {
  const { data, act } = useBackend<Data>();
  const {
    active,
    stability,
    shielding,
    cores,
    core_efficiency,
    core_stability,
    stored_power,
    has_fuel,
    fuel,
    fuel_max,
    fuel_injection,
  } = data;

  return (
    <Window width={480} height={460}>
      <Window.Content>
        <Section
          title="AntiMatter Control Panel"
          buttons={
            <>
              <Button
                icon="bolt"
                color={active ? 'good' : 'bad'}
                onClick={() => act('togglestatus')}
              >
                {active ? 'Injecting' : 'Standby'}
              </Button>{' '}
              <Button icon="sync" onClick={() => act('refreshicons')}>
                Force shielding update
              </Button>
            </>
          }
        >
          <LabeledList>
            <LabeledList.Item label="Instability">
              <Box inline bold color={stability < 50 ? 'bad' : 'good'}>
                {stability}%
              </Box>
            </LabeledList.Item>
            <LabeledList.Item label="Reactor parts">
              {shielding}
            </LabeledList.Item>
            <LabeledList.Item label="Cores">{cores}</LabeledList.Item>
            <LabeledList.Item label="Core efficiency">
              {core_efficiency}
            </LabeledList.Item>
            <LabeledList.Item label="Avg. core stability">
              <Box inline mr={1}>
                {core_stability}
              </Box>
              <Button onClick={() => act('refreshstability')}>Update</Button>
            </LabeledList.Item>
            <LabeledList.Item label="Last produced">
              {stored_power}
            </LabeledList.Item>
          </LabeledList>
        </Section>

        <Section
          title="Fuel"
          buttons={
            has_fuel ? (
              <Button icon="eject" color="bad" onClick={() => act('ejectjar')}>
                Eject
              </Button>
            ) : null
          }
        >
          {!has_fuel ? (
            <EmptyState>No fuel receptacle detected.</EmptyState>
          ) : (
            <LabeledList>
              <LabeledList.Item label="Units">
                {fuel} / {fuel_max}
              </LabeledList.Item>
              <LabeledList.Item label="Injection">
                <Button onClick={() => act('strengthdown')}>--</Button>{' '}
                <Box inline bold mx={1}>
                  {fuel_injection}
                </Box>
                <Button onClick={() => act('strengthup')}>++</Button>
              </LabeledList.Item>
            </LabeledList>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
