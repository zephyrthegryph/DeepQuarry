import type { DiagnosisBand } from '../common/Diagnosis';
import type { BodyScannerData } from '../generated/BodyScanner';

export type Data = BodyScannerData;

/** The scanned person (null while the scanner is empty); diagnosis is the shared report (UI_SCHEMA diagnosis_report). */
export type occupant = NonNullable<BodyScannerData['occupant']>;

export type DamageBand = DiagnosisBand;
