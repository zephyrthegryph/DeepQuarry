import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type SubstanceStack = {
  name: string;
  family: string;
  trigger: string;
  amount: number;
};

type LastResult = {
  relationship: string;
  magnitude: number;
  control: number;
  purity: number;
  hazard: string | null;
};

type KnowledgeRow = {
  name: string;
  family: string;
  energy: string;
  volatility: string;
  affinity: string;
  purity: string;
  relationships: string;
};

type Rig = {
  ceiling: number;
  volatility_mod: number;
  ambient: string;
};

type Data = {
  slot_a: SubstanceStack | null;
  slot_b: SubstanceStack | null;
  can_combine: BooleanLike;
  last_result: LastResult | null;
  knowledge: KnowledgeRow[];
  rig: Rig;
};

const StackSlot = (props: {
  stack: SubstanceStack | null;
  label: string;
  onEject: () => void;
}) => {
  const { stack, label, onEject } = props;
  return (
    <Section
      title={label}
      buttons={
        stack ? (
          <Button icon="eject" onClick={onEject}>
            Eject
          </Button>
        ) : null
      }
    >
      {stack ? (
        <LabeledList>
          <LabeledList.Item label="Substance">{stack.name}</LabeledList.Item>
          <LabeledList.Item label="Family">{stack.family}</LabeledList.Item>
          <LabeledList.Item label="Trigger">{stack.trigger}</LabeledList.Item>
          <LabeledList.Item label="Sheets">{stack.amount}</LabeledList.Item>
        </LabeledList>
      ) : (
        <Box color="label">Empty — load a substance material stack.</Box>
      )}
    </Section>
  );
};

export const SubstanceCombiner = () => {
  const { act, data } = useBackend<Data>();
  const {
    slot_a,
    slot_b,
    can_combine,
    last_result,
    knowledge = [],
    rig,
  } = data;

  return (
    <Window width={460} height={600} title="Substance Combiner">
      <Window.Content scrollable>
        <Stack vertical fill>
          <Stack.Item>
            <StackSlot
              stack={slot_a}
              label="Input A"
              onEject={() => act('eject_a')}
            />
          </Stack.Item>
          <Stack.Item>
            <StackSlot
              stack={slot_b}
              label="Input B"
              onEject={() => act('eject_b')}
            />
          </Stack.Item>
          {rig ? (
            <Stack.Item>
              <Section title="Rig & Environment">
                <LabeledList>
                  <LabeledList.Item label="Containment ceiling">
                    {rig.ceiling} magnitude
                  </LabeledList.Item>
                  <LabeledList.Item label="Ambient">
                    {rig.ambient}
                  </LabeledList.Item>
                  <LabeledList.Item label="Volatility shift">
                    <Box
                      color={
                        rig.volatility_mod > 0
                          ? 'bad'
                          : rig.volatility_mod < 0
                            ? 'good'
                            : 'label'
                      }
                    >
                      {rig.volatility_mod > 0 ? '+' : ''}
                      {rig.volatility_mod}
                    </Box>
                  </LabeledList.Item>
                </LabeledList>
              </Section>
            </Stack.Item>
          ) : null}
          <Stack.Item>
            <Section>
              <Button
                fluid
                icon="flask"
                color="good"
                textAlign="center"
                disabled={!can_combine}
                onClick={() => act('combine')}
              >
                Combine
              </Button>
            </Section>
          </Stack.Item>
          <Stack.Item grow>
            <Section title="Last Result">
              {last_result ? (
                <>
                  <LabeledList>
                    <LabeledList.Item label="Relationship">
                      {last_result.relationship}
                    </LabeledList.Item>
                    <LabeledList.Item label="Magnitude">
                      {last_result.magnitude}
                    </LabeledList.Item>
                    <LabeledList.Item label="Control">
                      {last_result.control}
                    </LabeledList.Item>
                    <LabeledList.Item label="Purity">
                      {last_result.purity}
                    </LabeledList.Item>
                  </LabeledList>
                  {last_result.hazard ? (
                    <Box bold color="bad" mt={1}>
                      HAZARD: {last_result.hazard}
                    </Box>
                  ) : null}
                </>
              ) : (
                <Box color="label">
                  No combination run yet. Results appear here.
                </Box>
              )}
            </Section>
          </Stack.Item>
          <Stack.Item grow>
            <Section title="Field Notes (this round)">
              {knowledge.length === 0 ? (
                <Box color="label">
                  Nothing learned yet. Combine a source with itself to probe its
                  properties; combine two sources to map their resonance.
                </Box>
              ) : (
                <Table>
                  <Table.Row header>
                    <Table.Cell>Source</Table.Cell>
                    <Table.Cell>Fam</Table.Cell>
                    <Table.Cell>E</Table.Cell>
                    <Table.Cell>V</Table.Cell>
                    <Table.Cell>A</Table.Cell>
                    <Table.Cell>P</Table.Cell>
                    <Table.Cell>Resonance vs</Table.Cell>
                  </Table.Row>
                  {knowledge.map((row) => (
                    <Table.Row key={row.name}>
                      <Table.Cell>{row.name}</Table.Cell>
                      <Table.Cell>{row.family}</Table.Cell>
                      <Table.Cell>{row.energy}</Table.Cell>
                      <Table.Cell>{row.volatility}</Table.Cell>
                      <Table.Cell>{row.affinity}</Table.Cell>
                      <Table.Cell>{row.purity}</Table.Cell>
                      <Table.Cell>{row.relationships}</Table.Cell>
                    </Table.Row>
                  ))}
                </Table>
              )}
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
