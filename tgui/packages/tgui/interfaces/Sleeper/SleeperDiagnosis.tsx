import { useBackend } from 'tgui/backend';

import {
  DiagnosisFindingsSection,
  DiagnosisHintsSection,
} from '../common/Diagnosis';
import type { Data } from './types';

// The sleeper's own triage sensors: findings and what they respond to.
export const SleeperDiagnosis = (props) => {
  const { data } = useBackend<Data>();
  const { diagnosis } = data.occupant;
  return (
    <>
      <DiagnosisFindingsSection findings={diagnosis.findings} />
      <DiagnosisHintsSection hints={diagnosis.hints} />
    </>
  );
};
