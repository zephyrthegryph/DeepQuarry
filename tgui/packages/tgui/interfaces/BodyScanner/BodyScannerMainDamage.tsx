import { Box, Section } from 'tgui-core/components';

import { BAND_INFO } from './constants';
import type { DamageBand, occupant } from './types';

// Whole-body qualitative damage panel. One pill per damage kind; the DM
// builder always emits all kinds in a stable order, even when their band
// is "uninjured", so the layout doesn't reshuffle as the patient changes.
export const BodyScannerMainDamage = (props: { occupant: occupant }) => {
  const { occupant } = props;
  const panel = occupant.damagePanel || [];
  if (!panel.length) {
    return null;
  }
  return (
    <Section title="Damage">
      <Box
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill, minmax(160px, 1fr))',
          gap: '0.4rem',
        }}
      >
        {panel.map((entry) => {
          const band = (entry.band as DamageBand) ?? 'uninjured';
          const info = BAND_INFO[band];
          return (
            <Box
              key={entry.kind}
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'baseline',
                padding: '0.25rem 0.5rem',
                borderRadius: '3px',
                background: 'rgba(255,255,255,0.04)',
              }}
            >
              <Box color="label" mr={1}>
                {entry.label}
              </Box>
              <Box color={info.color} bold>
                {info.label}
              </Box>
            </Box>
          );
        })}
      </Box>
    </Section>
  );
};
