import { Box } from 'tgui-core/components';

import {
  DiagnosisFindingsSection,
  DiagnosisHintsSection,
  DiagnosisVitalsSection,
} from '../common/Diagnosis';
import { BodyScannerMainAbnormalities } from './BodyScannerMainAbnormalities';
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
      <DiagnosisVitalsSection vitals={occupant.diagnosis.vitals} />
      <BodyScannerMainAbnormalities occupant={occupant} />
      <DiagnosisFindingsSection
        title="Scanner Findings"
        findings={occupant.diagnosis.findings}
      />
      <DiagnosisHintsSection hints={occupant.diagnosis.hints} />
      <BodyScannerMainOrgansExternal organs={occupant.extOrgan} />
      <BodyScannerMainOrgansInternal organs={occupant.intOrgan} />
      <BodyScannerMainReagents occupant={occupant} />
    </Box>
  );
};
