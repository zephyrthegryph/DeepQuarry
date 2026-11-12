import type { Diagnosis } from '../common/Diagnosis';
import type { MedigunData } from '../generated/Medigun';

// patient_diagnosis is the shared /datum/diagnosis report (common/Diagnosis).
export type Data = Omit<MedigunData, 'patient_diagnosis'> & {
  patient_diagnosis: Diagnosis | null;
};

export type ExamineData = MedigunData['examine_data'];

export type SModule = ExamineData['smodule'];
