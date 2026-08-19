import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  ProgressBar,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';

type Batch = {
  name: string;
  amount: number;
  phase: string;
  temperature: number;
  purity: number;
  grain: number;
  stress: number;
  porosity: number;
  homogeneity: number;
  hardness: number;
  toughness: number;
  conductivity: number;
  heat: number;
  corrosion: number;
  composition: { id: string; name: string; amount: number }[];
  history: string[];
};

type Data = {
  kind: string;
  batch: Batch | null;
  operations: string[];
  specifications: { name: string; fingerprint: string }[];
};

const Metric = (props: { label: string; value: number; bad?: boolean }) => (
  <LabeledList.Item label={props.label}>
    <ProgressBar
      value={props.value / 100}
      ranges={
        props.bad
          ? { good: [0, 0.25], average: [0.25, 0.55], bad: [0.55, 1] }
          : { bad: [0, 0.3], average: [0.3, 0.65], good: [0.65, 1] }
      }
    >
      {props.value}
    </ProgressBar>
  </LabeledList.Item>
);

export const MaterialScience = () => {
  const { act, data } = useBackend<Data>();
  const { kind, batch, operations = [], specifications = [] } = data;
  return (
    <Window width={720} height={650} title="Materials Workstation">
      <Window.Content scrollable>
        {!batch ? (
          <Section title={`${kind} module`}>
            <Box color="label">
              Load ordinary material sheets, processed stock, chemical dopants, or
              slime catalysts by hand. The machine never selects a canned alloy.
            </Box>
          </Section>
        ) : (
          <Stack vertical>
            <Stack.Item>
              <Section
                title={batch.name}
                buttons={
                  <>
                    <Button icon="eject" onClick={() => act('eject')}>
                      Eject stock
                    </Button>
                    <Button.Confirm color="bad" icon="trash" onClick={() => act('discard')}>
                      Discard
                    </Button.Confirm>
                  </>
                }
              >
                <LabeledList>
                  <LabeledList.Item label="Batch">
                    {batch.amount} sheets; {batch.phase}; {batch.temperature} K
                  </LabeledList.Item>
                  <Metric label="Purity" value={batch.purity} />
                  <Metric label="Homogeneity" value={batch.homogeneity} />
                  <Metric label="Porosity" value={batch.porosity} bad />
                  <Metric label="Internal stress" value={batch.stress} bad />
                  <LabeledList.Item label="Grain size">{batch.grain}</LabeledList.Item>
                </LabeledList>
              </Section>
            </Stack.Item>
            <Stack.Item>
              <Stack>
                <Stack.Item grow>
                  <Section title="Measured performance">
                    <LabeledList>
                      <Metric label="Hardness" value={batch.hardness} />
                      <Metric label="Toughness" value={batch.toughness} />
                      <Metric label="Conductivity" value={batch.conductivity} />
                      <Metric label="Heat resistance" value={batch.heat} />
                      <Metric label="Corrosion resistance" value={batch.corrosion} />
                    </LabeledList>
                  </Section>
                </Stack.Item>
                <Stack.Item grow>
                  <Section title="Composition">
                    <Table>
                      {batch.composition.map((part) => (
                        <Table.Row key={part.name}>
                          <Table.Cell>{part.name}</Table.Cell>
                          <Table.Cell textAlign="right">{part.amount}</Table.Cell>
                          {kind === 'electrochemical' && batch.composition.length > 1 ? (
                            <Table.Cell textAlign="right">
                              <Button
                                compact
                                icon="filter"
                                tooltip="Separate this constituent as an electrolytic deposit"
                                onClick={() => act('separate', { component: part.id })}
                              >
                                Separate
                              </Button>
                            </Table.Cell>
                          ) : null}
                        </Table.Row>
                      ))}
                    </Table>
                  </Section>
                </Stack.Item>
              </Stack>
            </Stack.Item>
            <Stack.Item>
              <Section title="Physical operations">
                {operations.map((operation) => (
                  <Button
                    key={operation}
                    icon="gears"
                    onClick={() => act('process', { process: operation })}
                  >
                    {operation}
                  </Button>
                ))}
                <Button icon="certificate" onClick={() => act('certify')}>
                  Print test certificate
                </Button>
                <Button icon="floppy-disk" onClick={() => act('save_spec')}>
                  Save specification
                </Button>
              </Section>
            </Stack.Item>
            <Stack.Item>
              <Section title="Process history">
                {batch.history.length ? (
                  batch.history.map((entry, index) => (
                    <Box key={`${entry}-${index}`}>{index + 1}. {entry}</Box>
                  ))
                ) : (
                  <Box color="label">Raw feedstock; no controlled treatment recorded.</Box>
                )}
              </Section>
            </Stack.Item>
          </Stack>
        )}
        <Section title="Saved material specifications" mt={1}>
          {specifications.length
            ? specifications.map((spec) => (
                <Box key={spec.fingerprint}>{spec.name} — {spec.fingerprint}</Box>
              ))
            : <Box color="label">No specifications saved this shift.</Box>}
        </Section>
      </Window.Content>
    </Window>
  );
};
