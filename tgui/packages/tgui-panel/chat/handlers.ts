import * as z from 'zod';
import { chatRenderer } from './renderer';

/**
 * The sequence numbers of the messages shown, for the duplicate check: the most recent SEEN_KEPT only (a resent copy arrives within moments),
 * not every message of the session, which grew without end and made each message's check a scan of all of them.
 */
const SEEN_KEPT = 4096;
const seen = new Set<number>();
const seenOrder: number[] = [];
let lastSequence: number | null = null;
const sequences_requested: number[] = [];

/** Records `sequence` as shown, forgetting the oldest past SEEN_KEPT. */
export function markSeen(sequence: number): void {
  seen.add(sequence);
  seenOrder.push(sequence);
  if (seenOrder.length > SEEN_KEPT) seen.delete(seenOrder.shift()!);
  lastSequence = sequence;
}

/** The sequence number of the last message shown, or null before any: a moved chat window asks the server for what follows (chat/ready). */
export function lastShownSequence(): number | null {
  return lastSequence;
}

/** How many sequence numbers the duplicate check holds (tests). */
export function seenCount(): number {
  return seen.size;
}

const messageSchema = z.object({
  sequence: z.number().int().nonnegative(),
  content: z.any(),
});

type ChatMessage = z.infer<typeof messageSchema>;

function pushMessage(message: ChatMessage): void {
  markSeen(message.sequence);
  chatRenderer.processBatch([message.content], {
    doArchive: true,
  });
}

export function chatMessage(payload: string): void {
  let message: ChatMessage;
  try {
    const parsed = JSON.parse(payload);
    message = messageSchema.parse(parsed);
  } catch (err) {
    console.error(err);
    return;
  }

  if (seen.has(message.sequence)) {
    return;
  }

  if (lastSequence === null) {
    pushMessage(message);
    return;
  }

  if (sequences_requested.includes(message.sequence)) {
    sequences_requested.splice(
      sequences_requested.indexOf(message.sequence),
      1,
    );
    pushMessage(message);
    return;
  }

  // if we are receiving a message we requested, we can stop reliability checks
  const expected_sequence = lastSequence + 1;
  if (message.sequence !== expected_sequence) {
    for (let req = expected_sequence; req < message.sequence; req++) {
      sequences_requested.push(req);
      Byond.sendMessage('chat/resend', req);
    }
  }

  pushMessage(message);
}
