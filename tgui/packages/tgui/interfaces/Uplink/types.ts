import type { UplinkData } from '../generated/Uplink';

export type Data = UplinkData;

export type Item = NonNullable<
  UplinkData['categories'][number]['items']
>[number];
