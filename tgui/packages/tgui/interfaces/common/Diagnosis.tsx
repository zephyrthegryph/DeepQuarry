// Shared rendering of a /datum/diagnosis (DM: diagnosis/renderers.dm,
// report_data()). Every medical interface shows the same report: vitals plus
// findings, with treatment hints when the instrument gives them.

import type { ReactNode } from 'react';
import {
  Box,
  LabeledList,
  Section,
  Table,
  Tooltip,
} from 'tgui-core/components';
import type { DiagnosisReport as DiagnosisShape } from '../generated/_schemas';
import { Label } from 'tgui/components/Label';

/** The report's type comes from its DM shape (UI_SCHEMA diagnosis_report, generated/_schemas). */
export type Diagnosis = DiagnosisShape;
export type DiagnosisBand = Diagnosis['band'];
export type DiagnosisTrend = NonNullable<DiagnosisFinding['trend']>;
export type DiagnosisFinding = Diagnosis['findings'][number];
export type HeartRhythm = NonNullable<DiagnosisVitals['heartRhythm']>;
export type DiagnosisVitals = Diagnosis['vitals'];
export type DiagnosisPartKind = NonNullable<DiagnosisPart['kind']>;
export type DiagnosisPart = Diagnosis['parts'][number];
export type DiagnosisHint = Diagnosis['hints'][number];

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

export const HEART_RHYTHM: Record<
  HeartRhythm,
  { label: string; color: string }
> = {
  sinus: { label: 'Normal sinus rhythm', color: 'good' },
  post_arrest: { label: 'Sinus rhythm (post-arrest)', color: 'average' },
  tachy: { label: 'Irregular tachycardia', color: 'average' },
  vfib: { label: 'Ventricular fibrillation - SHOCKABLE', color: 'bad' },
  asystole: { label: 'Asystole - not shockable', color: 'bad' },
};

const isSet = <T,>(value: T | null | undefined): value is T =>
  value !== null && value !== undefined;

// A vital outside its normal range reads in warning colours.
const rangeColor = (value: number, low: number, high: number) =>
  value < low || value > high ? 'bad' : 'good';

export const DiagnosisVitalsList = (props: {
  vitals: DiagnosisVitals;
  /** Items shown first, in the same list so their values share its column. */
  before?: ReactNode;
}) => {
  const { vitals, before } = props;
  const pressure = vitals.bloodPressure;
  return (
    <LabeledList>
      {before}
      {isSet(vitals.heartRate) ? (
        <LabeledList.Item
          label="Heart Rate"
          color={rangeColor(vitals.heartRate, 50, 110)}
        >
          {vitals.heartRate} bpm
        </LabeledList.Item>
      ) : null}
      {vitals.heartRhythm ? (
        <LabeledList.Item
          label="Rhythm"
          color={HEART_RHYTHM[vitals.heartRhythm].color}
        >
          {HEART_RHYTHM[vitals.heartRhythm].label}
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
          color={rangeColor(vitals.oxygenation, 92, 100)}
        >
          {vitals.oxygenation}%
        </LabeledList.Item>
      ) : null}
      {isSet(vitals.respiratoryRate) ? (
        <LabeledList.Item
          label="Respiration"
          color={rangeColor(vitals.respiratoryRate, 8, 25)}
        >
          {vitals.respiratoryRate} /min
        </LabeledList.Item>
      ) : null}
      {isSet(vitals.temperature) ? (
        <LabeledList.Item
          label="Temperature"
          color={rangeColor(vitals.temperature, 35, 38.5)}
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
          color={rangeColor(vitals.bloodPercent, 85, 200)}
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
        <Label inline mr={1} fontSize="0.85em">
          SIGN
        </Label>
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
        <Label fontSize="0.85em" ml={2}>
          {finding.hint}
        </Label>
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
