import { Box, Section, Table } from 'tgui-core/components';

import { BAND_INFO } from './constants';
import { germStatus, reduceOrganStatus } from './functions';
import type { DamageBand, internalOrgan } from './types';

export const BodyScannerMainOrgansInternal = (props: {
  organs: internalOrgan[];
}) => {
  const { organs } = props;

  if (organs.length === 0) {
    return (
      <Section title="Internal Organs">
        <Box color="label">N/A</Box>
      </Section>
    );
  }

  return (
    <Section title="Internal Organs">
      <Table>
        <Table.Row header>
          <Table.Cell>Name</Table.Cell>
          <Table.Cell textAlign="center">Injury</Table.Cell>
          <Table.Cell textAlign="right">Findings</Table.Cell>
        </Table.Row>
        {organs.map((o, i) => {
          const band = (o.injuryBand as DamageBand) ?? 'uninjured';
          const info = BAND_INFO[band];
          return (
            <Table.Row key={i} style={{ textTransform: 'capitalize' }}>
              <Table.Cell width="30%">{o.name}</Table.Cell>
              <Table.Cell textAlign="center">
                {o.missing ? (
                  <Box color="bad" bold inline>
                    Missing
                  </Box>
                ) : (
                  <Box color={info.color} bold inline>
                    {info.label}
                  </Box>
                )}
              </Table.Cell>
              <Table.Cell textAlign="right" width="40%">
                <Box color="average" inline>
                  {reduceOrganStatus([
                    !!o.germ_level && germStatus(o.germ_level),
                    !!o.inflamed && 'Appendicitis detected.',
                  ])}
                </Box>
                <Box inline>
                  {reduceOrganStatus([
                    o.robotic === 1 && 'Robotic',
                    o.robotic === 2 && 'Assisted',
                    !!o.dead && <Box color="bad">DEAD</Box>,
                  ])}
                </Box>
              </Table.Cell>
            </Table.Row>
          );
        })}
      </Table>
    </Section>
  );
};
