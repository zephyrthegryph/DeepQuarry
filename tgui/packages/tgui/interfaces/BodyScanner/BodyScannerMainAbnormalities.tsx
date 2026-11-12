import { Box, Section } from 'tgui-core/components';

import { abnormalities } from './constants';
import type { occupant } from './types';
import { Label } from 'tgui/components/Label';

export const BodyScannerMainAbnormalities = (props: { occupant: occupant }) => {
  const { occupant } = props;

  const hasAbnormalities =
    occupant.hasBorer ||
    occupant.blind ||
    occupant.colourblind ||
    occupant.nearsighted ||
    occupant.brokenspine ||
    occupant.hasVirus ||
    occupant.husked ||
    occupant.hasWithdrawl ||
    occupant.humanPrey ||
    occupant.livingPrey ||
    occupant.objectPrey ||
    occupant.hasAllergens;

  if (!hasAbnormalities) {
    return (
      <Section title="Abnormalities">
        <Label>No abnormalities found.</Label>
      </Section>
    );
  }

  return (
    <>
      <Section title="Abnormalities">
        {abnormalities.map(([flag, color, text]) => {
          if (occupant[flag]) {
            return (
              <Box key={flag} color={color} bold={color === 'bad'}>
                {text(occupant)}
              </Box>
            );
          }
          return undefined;
        })}
      </Section>
      {occupant.allergens ? (
        <Section title="Allergens">
          {occupant.allergens.map((allergy) => (
            <Box key={allergy} color="bad">
              {allergy}
            </Box>
          ))}
        </Section>
      ) : (
        ''
      )}
    </>
  );
};
