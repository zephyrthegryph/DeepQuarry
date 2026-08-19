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
  hardness: number | null;
  toughness: number | null;
  conductivity: number | null;
  heat: number | null;
  corrosion: number | null;
  composition: { id: string; name: string; amount: number }[];
  history: string[];
  structure: Record<string, number> | null;
  atmosphere: string;
  yield: number;
  energy: number;
  cost: number;
  unitCost: number;
  costBreakdown: Record<string, number>;
  hazard: number;
  roles: Record<string, boolean>;
  melting: number;
};

type Data = {
  kind: string;
  batch: Batch | null;
  operations: string[];
  operationAvailability: Record<string, boolean>;
  specifications: { name: string; fingerprint: string; matches: boolean; route: string[] }[];
  processing: boolean;
};

const Metric = (props: { label: string; value: number | null; bad?: boolean }) => props.value === null ? (
  <LabeledList.Item label={props.label} color="label">Not tested</LabeledList.Item>
) : (
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
  const { kind, batch, operations = [], operationAvailability = {}, specifications = [], processing } = data;
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
                  <LabeledList.Item label="Melting point">{batch.melting} K</LabeledList.Item>
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
                      <LabeledList.Item label="Usable yield">{batch.yield}%</LabeledList.Item>
                      <LabeledList.Item label="Process energy">{batch.energy}</LabeledList.Item>
                      <LabeledList.Item label="Total expense">{batch.cost} Th</LabeledList.Item>
                      <LabeledList.Item label="Cost / usable sheet">{batch.unitCost} Th</LabeledList.Item>
                      <LabeledList.Item label="Process hazard">
                        <Box color={batch.hazard >= 75 ? 'bad' : batch.hazard >= 45 ? 'average' : 'good'}>{batch.hazard}%</Box>
                      </LabeledList.Item>
                    </LabeledList>
                  </Section>
                </Stack.Item>
                <Stack.Item grow>
                  <Section title="Composition">
                    <Box color="label" mb={1}>{Object.keys(batch.roles).join(' • ')}</Box>
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
              <Section title="Production expense ledger">
                <Table>
                  {Object.entries(batch.costBreakdown).map(([category, value]) => (
                    <Table.Row key={category}>
                      <Table.Cell>{category}</Table.Cell>
                      <Table.Cell textAlign="right">
                        {category === 'usable_output' ? `${value} sheets` : `${value} Th`}
                      </Table.Cell>
                    </Table.Row>
                  ))}
                </Table>
                <Box color="label" mt={1}>
                  Waste value is informational: the lost material is already included in purchased feedstock. Recovery is credited against total expense.
                </Box>
              </Section>
            </Stack.Item>
            <Stack.Item>
              <Section title="Physical operations">
                {kind === 'thermal' ? (
                  <Box color="label" mb={1}>
                    Anneal {Math.round(batch.melting * 0.4)}–{Math.round(batch.melting * 0.75)} K;
                    forge {Math.round(batch.melting * 0.45)}–{Math.round(batch.melting * 0.9)} K;
                    solution treat above {Math.round(batch.melting * 0.62)} K before quenching;
                    temper {Math.round(batch.melting * 0.18)}–{Math.round(batch.melting * 0.48)} K.
                  </Box>
                ) : null}
                {kind === 'thermal' ? (
                  <Box mb={1}>
                    Atmosphere: {batch.atmosphere}{' '}
                    {['air', 'nitrogen', 'vacuum', 'hydrogen'].map((value) => (
                      <Button
                        key={value}
                        disabled={processing}
                        selected={batch.atmosphere === value}
                        onClick={() => act('atmosphere', { value })}
                      >
                        {value}
                      </Button>
                    ))}
                  </Box>
                ) : null}
                {operations.map((operation) => (
                  operation === 'quench' ? (
                    ['water', 'oil', 'cryo'].map((medium) => (
                      <Button key={`${operation}-${medium}`} icon="snowflake" disabled={processing || !operationAvailability[operation]} onClick={() => act('process', { process: operation, option: medium })}>
                        {operation}: {medium}
                      </Button>
                    ))
                  ) : (
                    <Button
                      key={operation}
                      icon="gears"
                      disabled={processing || !operationAvailability[operation]}
                      onClick={() => act('process', { process: operation })}
                    >
                      {operation}
                    </Button>
                  )
                ))}
                {processing ? <Box color="average" mt={1}>Physical cycle in progress…</Box> : null}
                {kind === 'testing' ? (
                  <Box mt={1}>
                    {['spectrometry', 'microscopy', 'hardness indentation', 'conductivity probe', 'tensile test', 'corrosion exposure'].map((test) => (
                      <Button key={test} icon="vial" tooltip={['tensile test', 'corrosion exposure'].includes(test) ? 'Destructive: consumes one sheet coupon' : 'Non-destructive'} onClick={() => act('test', { test })}>{test}</Button>
                    ))}
                    <Button icon="certificate" onClick={() => act('certify')}>Print test certificate</Button>
                  </Box>
                ) : null}
                <Button icon="floppy-disk" onClick={() => act('save_spec')}>
                  Save specification
                </Button>
              </Section>
            </Stack.Item>
            {batch.structure ? (
              <Stack.Item>
                <Section title="Microscopy">
                  {Object.entries(batch.structure).map(([name, fraction]) => (
                    <Box key={name}>{name}: {fraction}%</Box>
                  ))}
                </Section>
              </Stack.Item>
            ) : null}
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
                <Box key={spec.fingerprint} color={spec.matches ? 'good' : undefined}>
                  {spec.name} — {spec.fingerprint} {spec.matches ? '(within tolerance)' : ''}
                </Box>
              ))
            : <Box color="label">No specifications saved this shift.</Box>}
        </Section>
      </Window.Content>
    </Window>
  );
};
