import { createQueue } from './handlers/chunking';

const DIRECT_TOPIC_LIMIT = 1024;
let messageSequence = 0;

function topicLength(type: string, payload: string): number {
  return Object.entries({
    type,
    payload,
    tgui: 1,
    windowId: Byond.windowId,
  }).reduce(
    (url, [key, value], index) =>
      `${url}${index ? '&' : '?'}${encodeURIComponent(key)}=${encodeURIComponent(value)}`,
    '',
  ).length;
}

/**
 * Sends an arbitrary TGUI message without silently losing payloads to BYOND's
 * small Topic URL limit. This shares the existing acknowledged chunk transport
 * used by large actions instead of creating another wire protocol.
 */
export function sendByondMessage(
  type: string,
  payload: Record<string, unknown> = {},
): void {
  const encoded = JSON.stringify(payload);
  if (topicLength(type, encoded) <= DIRECT_TOPIC_LIMIT) {
    Byond.sendMessage(type, payload);
    return;
  }

  const chunks = encoded.split(encodedChunkSplitter);
  const id = `${Date.now()}-${++messageSequence}`;
  createQueue({ id, chunks });
  Byond.sendMessage('oversizedPayloadRequest', {
    type,
    id,
    chunkCount: chunks.length,
  });
}

const encodedChunkSplitter = {
  [Symbol.split]: (value: string): string[] => {
    const characters = [...value];
    const chunks: string[] = [];
    let start = 0;
    while (start < characters.length) {
      let low = start + 1;
      let high = characters.length;
      let best = low;
      while (low <= high) {
        const middle = Math.floor((low + high) / 2);
        const candidate = characters.slice(start, middle).join('');
        if (encodeURIComponent(candidate).length <= DIRECT_TOPIC_LIMIT) {
          best = middle;
          low = middle + 1;
        } else {
          high = middle - 1;
        }
      }
      chunks.push(characters.slice(start, best).join(''));
      start = best;
    }
    return chunks;
  },
};
