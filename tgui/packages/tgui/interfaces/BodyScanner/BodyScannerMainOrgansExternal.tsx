import { Box, Section, Table } from 'tgui-core/components';

import { BAND_INFO } from './constants';
import { germStatus, reduceOrganStatus } from './functions';
import type { DamageBand, externalOrgan } from './types';

export const BodyScannerMainOrgansExternal = (props: {
  organs: externalOrgan[];
}) => {
  const { organs } = props;

  if (organs.length === 0) {
    return (
      <Section title="External Organs">
        <Box color="label">N/A</Box>
      </Section>
    );
  }

  return (
    <Section title="External Organs">
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
                <Box color={info.color} bold inline>
                  {info.label}
                </Box>
              </Table.Cell>
              <Table.Cell textAlign="right" width="40%">
                <Box color="average" inline>
                  {reduceOrganStatus([
                    o.internalBleeding && 'Internal bleeding',
                    !!o.status.bleeding && 'External bleeding',
                    o.lungRuptured && 'Ruptured lung',
                    o.status.destroyed && 'Destroyed',
                    !!o.status.broken && o.status.broken,
                    germStatus(o.germ_level),
                    !!o.open && 'Open incision',
                  ])}
                </Box>
                <Box inline>
                  {reduceOrganStatus([
                    !!o.status.splinted && 'Splinted',
                    !!o.status.robotic && 'Robotic',
                    !!o.status.dead && <Box color="bad">DEAD</Box>,
                  ])}
                  {reduceOrganStatus(
                    o.implants.map((s) =>
                      s.known ? s.name : 'Unknown object',
                    ),
                  )}
                </Box>
              </Table.Cell>
            </Table.Row>
          );
        })}
      </Table>
    </Section>
  );
};
