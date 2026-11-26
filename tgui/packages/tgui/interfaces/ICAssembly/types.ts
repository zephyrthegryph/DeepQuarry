import type { ICAssemblyData } from '../generated/ICAssembly';

export type Data = ICAssemblyData;

export type ComponentPosition = Data['component_positions'][number];

export type CircuitData = Data['circuits'][number];

export type PortData = CircuitData['inputs'][number];

export type LinkedPortData = PortData['linked'][number];

export enum PortTypes {
  IC_FORMAT_ANY = '<ANY>',
  IC_FORMAT_STRING = '<TEXT>',
  IC_FORMAT_CHAR = '<CHAR>',
  IC_FORMAT_COLOR = '<COLOR>',
  IC_FORMAT_NUMBER = '<NUM>',
  IC_FORMAT_DIR = '<DIR>',
  IC_FORMAT_BOOLEAN = '<BOOL>',
  IC_FORMAT_REF = '<REF>',
  IC_FORMAT_LIST = '<LIST>',
  IC_FORMAT_PULSE = '<PULSE>',
}

export const PortTypesToColor = {
  [PortTypes.IC_FORMAT_ANY]: 'olive',
  [PortTypes.IC_FORMAT_STRING]: 'green',
  [PortTypes.IC_FORMAT_CHAR]: 'teal',
  [PortTypes.IC_FORMAT_COLOR]: 'pink',
  [PortTypes.IC_FORMAT_NUMBER]: 'blue',
  [PortTypes.IC_FORMAT_DIR]: 'brown',
  [PortTypes.IC_FORMAT_BOOLEAN]: 'red',
  [PortTypes.IC_FORMAT_REF]: 'orange',
  [PortTypes.IC_FORMAT_LIST]: 'average',
  [PortTypes.IC_FORMAT_PULSE]: 'yellow',
};

export const ABSOLUTE_Y_OFFSET = -32;
export const MOUSE_BUTTON_LEFT = 0;
export const TIME_UNTIL_PORT_RELEASE_WORKS = 100;
