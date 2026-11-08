import { loadStyleSheet } from 'common/assets';
import { EventBus } from 'tgui-core/eventbus';
import { playMusic, stopMusic } from '../audio/handlers';
import { chatMessage } from '../chat/handlers';
import { columnHost } from '../column/host';
import {
  availableChannels,
  focusInput,
  languageRules,
  radioChannels,
} from '../input/handlers';
import { chatLayout } from '../layout/handlers';
import { pingReply, pingSoft } from '../ping/handlers';
import {
  handleTelemetryData,
  telemetryRequest,
  testTelemetryCommand,
} from '../telemetry/handlers';
import { handleLoadAssets } from './handlers/assets';
import { connected } from './handlers/connected';
import { roundrestart } from './handlers/roundrestart';

/** The column's own messages (column/host.ts): its windows open, talk and close through these. */
const column = (type: string) => (payload: unknown) =>
  columnHost.receive(type, payload);

const listeners = {
  'col/open': column('col/open'),
  'col/msg': column('col/msg'),
  'col/close': column('col/close'),
  'col/drop-check': column('col/drop-check'),
  'col/init': column('col/init'),
  'asset/stylesheet': loadStyleSheet,
  'asset/mappings': handleLoadAssets,
  'audio/playMusic': playMusic,
  'audio/stopMusic': stopMusic,
  'chat/channels': availableChannels,
  'chat/focusInput': focusInput,
  'chat/languageRules': languageRules,
  'chat/layout': chatLayout,
  'chat/message': chatMessage,
  'chat/radioChannels': radioChannels,
  connected,
  'ping/reply': pingReply,
  'ping/soft': pingSoft,
  roundrestart,
  'telemetry/request': telemetryRequest,
  testTelemetryCommand,
  update: handleTelemetryData,
} as const;

export const bus = new EventBus(listeners);
