import type { VorePanelExportData } from '../generated/VorePanelExport';

export type Data = VorePanelExportData;

export type Belly = VorePanelExportData['bellies'][number];

export type Soulcatcher = NonNullable<VorePanelExportData['soulcatcher']>;

type Formatter<T> = (val: T) => string;

export type SettingItem<T = any> = {
  label: string;
  value: T;
  formatter?: Formatter<T>;
};

export type EmoteEntry = { label: string; messages?: string[] };
