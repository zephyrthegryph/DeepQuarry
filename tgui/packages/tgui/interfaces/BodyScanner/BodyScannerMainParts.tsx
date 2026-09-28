import { Box, Section, Table } from 'tgui-core/components';

import type { DiagnosisPart, DiagnosisPartKind } from '../common/Diagnosis';
import { BAND_INFO } from './constants';

// Limb and organ rows come straight from the scanner's diagnosis parts
// (diagnose_parts on the DM side); the UI only renders them.
export const BodyScannerMainParts = (props: {
  title: string;
  kind: DiagnosisPartKind;
  parts: DiagnosisPart[];
}) => {
  const { title, kind, parts } = props;
  const rows = parts.filter((p) => (p.kind ?? 'external') === kind);

  if (rows.length === 0) {
    return (
      <Section title={title}>
        <Box color="label">N/A</Box>
      </Section>
    );
  }

  return (
    <Section title={title}>
      <Table>
        <Table.Row header>
          <Table.Cell>Name</Table.Cell>
          <Table.Cell textAlign="center">Injury</Table.Cell>
          <Table.Cell textAlign="right">Findings</Table.Cell>
        </Table.Row>
        {rows.map((p) => {
          const missing = p.flags.includes('missing');
          const info = BAND_INFO[p.band] ?? BAND_INFO.uninjured;
          return (
            <Table.Row key={p.name} style={{ textTransform: 'capitalize' }}>
              <Table.Cell width="30%">{p.name}</Table.Cell>
              <Table.Cell textAlign="center">
                <Box color={missing ? 'bad' : info.color} bold inline>
                  {missing ? 'Missing' : info.label}
                </Box>
              </Table.Cell>
              <Table.Cell textAlign="right" width="40%">
                {p.flags
                  .filter((f) => f !== 'missing')
                  .map((f) => (
                    <Box key={f} color={f === 'necrotic' ? 'bad' : 'average'}>
                      {f}
                    </Box>
                  ))}
                {(p.implants ?? []).map((name, i) => (
                  <Box key={`${name}-${i}`}>{name}</Box>
                ))}
              </Table.Cell>
            </Table.Row>
          );
        })}
      </Table>
    </Section>
  );
};
