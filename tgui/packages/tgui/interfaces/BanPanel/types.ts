import type { BanPanelData } from '../generated/BanPanel';

export type Data = BanPanelData;

export type DropdownEntry = {
  displayText: string;
  value: string;
};

// This list is of the format: banid, bantime, bantype, reason, job, duration, expiration,
//     ckey, ackey, unbanned, unbanckey, unbantime, edits, ip, cid
export type DatabaseRecord = NonNullable<Data['database_records']>[number];
