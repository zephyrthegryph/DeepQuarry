import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Icon,
  LabeledList,
  Section,
  Stack,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import type { DNAModifierActions } from '../generated/DNAModifier';
import { stats } from './constants';
import type { Data } from './types';
import { StatBar } from 'tgui/components/StatBar';
import { Label } from 'tgui/components/Label';

export const DNAModifierOccupant = (props: { isDNAInvalid: BooleanLike }) => {
  const { act, data } = useBackend<Data, DNAModifierActions>();

  const { locked, hasOccupant, occupant } = data;

  return (
    <Section
      title="Occupant"
      buttons={
        <Stack>
          <Stack.Item>
            <Label inline mr="0.5rem">
              Door Lock:
            </Label>
          </Stack.Item>
          <Stack.Item>
            <Button
              disabled={!hasOccupant}
              selected={locked}
              icon={locked ? 'toggle-on' : 'toggle-off'}
              onClick={() => act('toggleLock')}
            >
              {locked ? 'Engaged' : 'Disengaged'}
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button
              disabled={!hasOccupant || locked}
              icon="user-slash"
              onClick={() => act('ejectOccupant')}
            >
              Eject
            </Button>
          </Stack.Item>
        </Stack>
      }
    >
      {hasOccupant ? (
        <>
          <Box>
            <LabeledList>
              <LabeledList.Item label="Name">{occupant.name}</LabeledList.Item>
              <StatBar
                label="Health"
                minValue={0}
                maxValue={1}
                value={occupant.health! / occupant.maxHealth!}
                ranges={{
                  good: [0.5, Infinity],
                  average: [0, 0.5],
                  bad: [-Infinity, 0],
                }}
              />
              <LabeledList.Item label="Status" color={stats[occupant.stat!][0]}>
                {stats[occupant.stat!][1]}
              </LabeledList.Item>
              <LabeledList.Divider />
            </LabeledList>
          </Box>
          {props.isDNAInvalid ? (
            <Box color="bad">
              <Icon name="exclamation-circle" />
              &nbsp; The occupant&apos;s DNA structure is ruined beyond
              recognition, please insert a subject with an intact DNA structure.
            </Box>
          ) : (
            <LabeledList>
              <StatBar
                label="Radiation"
                minValue={0}
                maxValue={1}
                value={occupant.radiationLevel! / 100}
                color="average"
              />
              <LabeledList.Item label="Unique Enzymes">
                {data.occupant.uniqueEnzymes ? (
                  data.occupant.uniqueEnzymes.toUpperCase()
                ) : (
                  <Box color="bad">
                    <Icon name="exclamation-circle" />
                    &nbsp; Unknown
                  </Box>
                )}
              </LabeledList.Item>
            </LabeledList>
          )}
        </>
      ) : (
        <Label>Cell unoccupied.</Label>
      )}
    </Section>
  );
};
