import { useBackend } from 'tgui/backend';

import {
  DiagnosisFindingsSection,
  DiagnosisHintsSection,
} from '../common/Diagnosis';
import type { SleeperActions, SleeperData } from '../generated/Sleeper';

// The sleeper's own triage sensors: findings and what they respond to.
export const SleeperDiagnosis = (props) => {
  const { data } = useBackend<SleeperData, SleeperActions>();
  const diagnosis = data.occupant?.diagnosis;
  if (!diagnosis) {
    return null;
  }
  return (
    <>
      <DiagnosisFindingsSection findings={diagnosis.findings} />
      <DiagnosisHintsSection hints={diagnosis.hints} />
    </>
  );
};
