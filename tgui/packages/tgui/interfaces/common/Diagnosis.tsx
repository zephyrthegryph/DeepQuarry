// Shared rendering of a /datum/diagnosis (DM: diagnosis/renderers.dm,
// report_data()). Every medical interface shows the same report: vitals plus
// findings, with treatment hints when the instrument gives them.

import {
  Box,
  LabeledList,
  Section,
  Table,
  Tooltip,
} from 'tgui-core/components';

export type DiagnosisBand =
  | 'uninjured'
  | 'minor'
  | 'moderate'
  | 'severe'
  | 'critical';

export type DiagnosisTrend = 'new' | 'worsening' | 'improving' | 'stable';

export type DiagnosisFinding = {
  name: string;
  kind: 'condition' | 'sign' | 'lesion' | 'wound';
  band: DiagnosisBand;
  location: string;
  description?: string | null;
  trend?: DiagnosisTrend | null;
  hint?: string | null;
};

export type DiagnosisVitals = {
  heartRate?: number | null;
  bloodPressure?: [number, number] | null;
  oxygenation?: number | null;
  respiratoryRate?: number | null;
  temperature?: number | null;
  consciousness?: string | null;
  bloodPercent?: number | null;
};

export type DiagnosisPart = {
  name: string;
  band: DiagnosisBand;
  flags: string[];
};

export type DiagnosisHint = {
  tag: string;
  label: string;
  band: DiagnosisBand;
};

export type Diagnosis = {
  status: 'alive' | 'critical' | 'dead';
  band: DiagnosisBand;
  vitals: DiagnosisVitals;
  findings: DiagnosisFinding[];
  parts: DiagnosisPart[];
  hints: DiagnosisHint[];
};

export const DIAGNOSIS_BAND: Record<
  DiagnosisBand,
  { label: string; color: string; rank: number }
> = {
  uninjured: { label: 'None', color: 'good', rank: 0 },
  minor: { label: 'Minor', color: 'olive', rank: 1 },
  moderate: { label: 'Moderate', color: 'average', rank: 2 },
  severe: { label: 'Severe', color: 'bad', rank: 3 },
  critical: { label: 'Critical', color: 'bad', rank: 4 },
};

const TREND: Record<
  DiagnosisTrend,
  { symbol: string; color: string; tooltip: string }
> = {
  new: {
    symbol: '*',
    color: 'label',
    tooltip: 'New finding: no prior scan to compare against.',
  },
  worsening: {
    symbol: '↑',
    color: 'bad',
    tooltip: 'Worsening since last scan.',
  },
  improving: {
    symbol: '↓',
    color: 'good',
    tooltip: 'Improving since last scan.',
  },
  stable: { symbol: '=', color: 'label', tooltip: 'Stable since last scan.' },
};

const isSet = (value: unknown) => value !== null && value !== undefined;

// A vital outside its normal range reads in warning colours.
const rangeColor = (value: number, low: number, high: number) =>
  value < low || value > high ? 'bad' : 'good';

export const DiagnosisVitalsList = (props: { vitals: DiagnosisVitals }) => {
  const { vitals } = props;
  const pressure = vitals.bloodPressure;
  return (
    <LabeledList>
      {isSet(vitals.heartRate) ? (
        <LabeledList.Item
          label="Heart Rate"
          color={rangeColor(vitals.heartRate as number, 50, 110)}
        >
          {vitals.heartRate} bpm
        </LabeledList.Item>
      ) : null}
      {pressure ? (
        <LabeledList.Item
          label="Blood Pressure"
          color={rangeColor(pressure[0], 90, 160)}
        >
          {pressure[0]}/{pressure[1]} mmHg
        </LabeledList.Item>
      ) : null}
      {isSet(vitals.oxygenation) ? (
        <LabeledList.Item
          label="SpO2"
          color={rangeColor(vitals.oxygenation as number, 92, 100)}
        >
          {vitals.oxygenation}%
        </LabeledList.Item>
      ) : null}
      {isSet(vitals.respiratoryRate) ? (
        <LabeledList.Item
          label="Respiration"
          color={rangeColor(vitals.respiratoryRate as number, 8, 25)}
        >
          {vitals.respiratoryRate} /min
        </LabeledList.Item>
      ) : null}
      {isSet(vitals.temperature) ? (
        <LabeledList.Item
          label="Temperature"
          color={rangeColor(vitals.temperature as number, 35, 38.5)}
        >
          {vitals.temperature}&deg;C
        </LabeledList.Item>
      ) : null}
      {vitals.consciousness ? (
        <LabeledList.Item
          label="Consciousness"
          color={vitals.consciousness === 'alert' ? 'good' : 'average'}
        >
          {vitals.consciousness}
        </LabeledList.Item>
      ) : null}
      {isSet(vitals.bloodPercent) ? (
        <LabeledList.Item
          label="Blood Volume"
          color={rangeColor(vitals.bloodPercent as number, 85, 200)}
        >
          {vitals.bloodPercent}%
        </LabeledList.Item>
      ) : null}
    </LabeledList>
  );
};

export const DiagnosisVitalsSection = (props: {
  vitals: DiagnosisVitals;
  title?: string;
}) => {
  const { vitals, title = 'Vitals' } = props;
  return (
    <Section title={title}>
      <DiagnosisVitalsList vitals={vitals} />
    </Section>
  );
};

const FindingRow = (props: { finding: DiagnosisFinding }) => {
  const { finding } = props;
  const band = DIAGNOSIS_BAND[finding.band] ?? DIAGNOSIS_BAND.minor;
  const trend = finding.trend ? TREND[finding.trend] : null;
  return (
    <Box mb="2px">
      {finding.kind === 'sign' ? (
        <Box inline mr={1} color="label" fontSize="0.85em">
          SIGN
        </Box>
      ) : (
        <Box
          inline
          mr={1}
          bold
          color={band.color}
          fontSize="0.85em"
          style={{ textTransform: 'uppercase' }}
        >
          {band.label}
        </Box>
      )}
      {trend ? (
        <Tooltip content={trend.tooltip} position="top">
          <Box inline mr={1} color={trend.color}>
            {trend.symbol}
          </Box>
        </Tooltip>
      ) : null}
      {finding.description ? (
        <Tooltip content={finding.description} position="top">
          <Box inline style={{ borderBottom: '1px dotted' }}>
            {finding.name}
          </Box>
        </Tooltip>
      ) : (
        <Box inline>{finding.name}</Box>
      )}
      {finding.hint ? (
        <Box color="label" fontSize="0.85em" ml={2}>
          {finding.hint}
        </Box>
      ) : null}
    </Box>
  );
};

// Findings grouped by location; unlocalised findings sit under "Systemic".
export const DiagnosisFindingsSection = (props: {
  findings: DiagnosisFinding[];
  title?: string;
}) => {
  const { findings, title = 'Findings' } = props;
  if (!findings.length) {
    return (
      <Section title={title}>
        <Box color="good">No abnormal findings.</Box>
      </Section>
    );
  }
  const byLocation: Record<string, DiagnosisFinding[]> = {};
  for (const finding of findings) {
    const key = finding.location || 'Systemic';
    if (!byLocation[key]) {
      byLocation[key] = [];
    }
    byLocation[key].push(finding);
  }
  return (
    <Section title={title}>
      <Table>
        {Object.keys(byLocation)
          .sort()
          .map((location) => (
            <Table.Row key={location}>
              <Table.Cell
                width="22%"
                color="label"
                style={{ textTransform: 'capitalize' }}
              >
                {location}
              </Table.Cell>
              <Table.Cell>
                {byLocation[location].map((finding) => (
                  <FindingRow
                    key={`${finding.kind}-${finding.name}`}
                    finding={finding}
                  />
                ))}
              </Table.Cell>
            </Table.Row>
          ))}
      </Table>
    </Section>
  );
};

// Treatment mechanisms the detected conditions respond to.
export const DiagnosisHintsSection = (props: { hints: DiagnosisHint[] }) => {
  const { hints } = props;
  if (!hints.length) {
    return null;
  }
  return (
    <Section title="Responds To">
      {hints.map((hint) => (
        <Box key={hint.tag} inline mr={2}>
          <Box inline color={DIAGNOSIS_BAND[hint.band]?.color ?? 'label'}>
            {hint.label}
          </Box>
        </Box>
      ))}
    </Section>
  );
};

// The full report: vitals, findings and hints.
export const DiagnosisReport = (props: { diagnosis: Diagnosis }) => {
  const { diagnosis } = props;
  return (
    <>
      <DiagnosisVitalsSection vitals={diagnosis.vitals} />
      <DiagnosisFindingsSection findings={diagnosis.findings} />
      <DiagnosisHintsSection hints={diagnosis.hints} />
    </>
  );
};
