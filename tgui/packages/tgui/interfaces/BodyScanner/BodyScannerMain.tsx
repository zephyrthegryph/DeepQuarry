import { Box } from 'tgui-core/components';

import { BodyScannerMainAbnormalities } from './BodyScannerMainAbnormalities';
import { BodyScannerMainDamage } from './BodyScannerMainDamage';
import { BodyScannerMainFindings } from './BodyScannerMainFindings';
import { BodyScannerMainOccupant } from './BodyScannerMainOccupant';
import { BodyScannerMainOrgansExternal } from './BodyScannerMainOrgansExternal';
import { BodyScannerMainOrgansInternal } from './BodyScannerMainOrgansInternal';
import { BodyScannerMainReagents } from './BodyScannerMainReagents';
import type { occupant } from './types';

export const BodyScannerMain = (props: { occupant: occupant }) => {
  const { occupant } = props;
  return (
    <Box>
      <BodyScannerMainOccupant occupant={occupant} />
      <BodyScannerMainAbnormalities occupant={occupant} />
      <BodyScannerMainFindings occupant={occupant} />
      <BodyScannerMainDamage occupant={occupant} />
      <BodyScannerMainOrgansExternal organs={occupant.extOrgan} />
      <BodyScannerMainOrgansInternal organs={occupant.intOrgan} />
      <BodyScannerMainReagents occupant={occupant} />
    </Box>
  );
};
