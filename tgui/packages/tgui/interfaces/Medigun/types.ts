import type { MedigunData } from '../generated/Medigun';

export type Data = MedigunData;

export type ExamineData = MedigunData['examine_data'];

export type SModule = ExamineData['smodule'];
