import type { Diagnosis, DiagnosisBand } from '../common/Diagnosis';
import type { BodyScannerData } from '../generated/BodyScanner';

// diagnosis is the shared /datum/diagnosis report (common/Diagnosis).
export type occupant = Omit<BodyScannerData['occupant'], 'diagnosis'> & {
  diagnosis: Diagnosis;
};

export type Data = Omit<BodyScannerData, 'occupant'> & {
  occupant: occupant;
};

export type DamageBand = DiagnosisBand;
