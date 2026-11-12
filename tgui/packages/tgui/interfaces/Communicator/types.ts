import type { CommunicatorData } from '../generated/Communicator';

export type Data = CommunicatorData;

export type ContactsTabData = Pick<Data, 'knownDevices'>;

export type WeatherTabData = Pick<Data, 'aircontents' | 'weather'>;

export type AirContent = Data['aircontents'][number];
