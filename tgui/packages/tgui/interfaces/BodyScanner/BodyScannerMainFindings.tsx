import { Box, Section, Table, Tooltip } from 'tgui-core/components';

import { BAND_INFO } from './constants';
import type { DamageBand, occupant, ScannerFinding } from './types';

// Each finding carries a "trend" computed by the DM side from severity
// delta since the last scan. Worsening = the condition is getting worse
// despite (or without) treatment; improving = chems / surgery are
// working; stable = neither. "new" appears on the first scan only.
const TREND_DISPLAY: Record<
  ScannerFinding['trend'],
  { symbol: string; color: string; tooltip: string }
> = {
  new: {
    symbol: '*',
    color: 'label',
    tooltip: 'New finding — no prior scan to compare against.',
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

// Scanner-detected findings — phrases produced by SYMPTOM_AUDIENCE_SCANNER
// symptoms currently active on the occupant. Grouped by organ so a medic
// reading the panel can map findings back to where they're treating.
export const BodyScannerMainFindings = (props: { occupant: occupant }) => {
  const { occupant } = props;
  const findings = occupant.scannerFindings || [];
  if (!findings.length) {
    return null;
  }
  // Group by organ. Empty-string organ goes under "Systemic".
  const byOrgan: Record<string, typeof findings> = {};
  for (const f of findings) {
    const key = f.organ || 'Systemic';
    if (!byOrgan[key]) byOrgan[key] = [];
    byOrgan[key].push(f);
  }
  const organs = Object.keys(byOrgan).sort();
  return (
    <Section title="Scanner Findings">
      <Table>
        {organs.map((organ) => (
          <Table.Row key={organ}>
            <Table.Cell
              width="22%"
              style={{ textTransform: 'capitalize' }}
              color="label"
            >
              {organ}
            </Table.Cell>
            <Table.Cell>
              {byOrgan[organ].map((f, i) => {
                const band = (f.severity as DamageBand) ?? 'minor';
                const info = BAND_INFO[band];
                const trend = TREND_DISPLAY[f.trend] || TREND_DISPLAY.new;
                return (
                  <Box key={i} mb="2px">
                    <Box
                      color={info.color}
                      bold
                      inline
                      mr={1}
                      fontSize="0.85em"
                      style={{ textTransform: 'uppercase' }}
                    >
                      {info.label}
                    </Box>
                    <Tooltip content={trend.tooltip} position="top">
                      <Box color={trend.color} inline mr={1}>
                        {trend.symbol}
                      </Box>
                    </Tooltip>
                    <Box inline>{f.phrase}</Box>
                    {f.stage ? (
                      <Box inline ml={1} color="label" fontSize="0.85em">
                        [{f.stage}]
                      </Box>
                    ) : null}
                  </Box>
                );
              })}
            </Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};
