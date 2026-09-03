import { logger } from '../logging';
import { profileAction } from '../profiling/hooks';
import { sendByondMessage } from './sendMessage';

/**
 * Sends an action to `ui_act` on `src_object` that this tgui window
 * is associated with.
 */
export function sendAct(
  action: string,
  payload: Record<string, unknown> = {},
): void {
  // Validate that payload is an object
  const isObject =
    typeof payload === 'object' && payload !== null && !Array.isArray(payload);
  if (!isObject) {
    logger.error(`Payload for act() must be an object, got this:`, payload);
    return;
  }

  const stringifiedPayload = JSON.stringify(payload);
  if (process.env.NODE_ENV === 'development') {
    profileAction(action, stringifiedPayload.length);
  }
  sendByondMessage(`act/${action}`, payload);
}
