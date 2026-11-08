/**
 * The one way a tgui page tells the server something failed. Every surface (a window's content, a script error, a
 * chunk, a message handler, a chat line) reports here; the server writes them under the `tgui_error` log context.
 */
export type UiErrorKind =
  | 'render'
  | 'chunk'
  | 'script'
  | 'handler'
  | 'prepare'
  | 'chat-message';

/** What the page did about it. */
export type UiErrorOutcome = 'retried' | 'error-screen' | 'continued';

export type UiError = {
  kind: UiErrorKind;
  /** The window, interface or view it happened in. */
  name: string;
  error: unknown;
  component?: string | null;
  outcome: UiErrorOutcome;
};

const MAX_STACK = 3000;
const MAX_COMPONENT = 1200;
/** The same failure inside this long is counted, not sent again. */
export const REPORT_DEDUPE_MS = 10000;
const RATE_WINDOW_MS = 60000;
const RATE_LIMIT = 30;

type Channel = (report: Record<string, unknown>) => void;

// A native window's messages go to its tgui datum; the column page sets its own (it has no datum).
let channel: Channel = (report) => Byond.sendMessage('wm/error', report);

/** How this page reaches the server. */
export function setErrorChannel(next: Channel) {
  channel = next;
}

const recent = new Map<string, { at: number; repeats: number }>();
let rateStart = 0;
let rateCount = 0;
let dropped = 0;

/** The text of anything thrown. */
export function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function reportUiError(report: UiError) {
  const now = Date.now();
  const message = errorText(report.error);
  const key = `${report.kind}|${report.name}|${report.outcome}|${message}`;
  const seen = recent.get(key);
  if (seen && now - seen.at < REPORT_DEDUPE_MS) {
    seen.repeats++;
    return;
  }
  if (now - rateStart >= RATE_WINDOW_MS) {
    rateStart = now;
    rateCount = 0;
  }
  if (rateCount >= RATE_LIMIT) {
    dropped++;
    return;
  }
  rateCount++;
  for (const [old, entry] of recent) {
    if (now - entry.at >= REPORT_DEDUPE_MS) recent.delete(old);
  }
  recent.set(key, { at: now, repeats: 0 });
  try {
    channel({
      window: Byond.windowId,
      kind: report.kind,
      name: report.name,
      outcome: report.outcome,
      message: message.slice(0, MAX_STACK),
      stack:
        report.error instanceof Error
          ? report.error.stack?.slice(0, MAX_STACK)
          : undefined,
      component: report.component?.slice(0, MAX_COMPONENT),
      repeats: seen?.repeats || undefined,
      dropped: dropped || undefined,
    });
    dropped = 0;
  } catch (failure) {
    // The reporter must never be what breaks the page.
    console.error('could not report a tgui error', failure);
  }
}

/** Forgets what was sent: a test's fresh start. */
export function resetErrorReports() {
  recent.clear();
  rateStart = 0;
  rateCount = 0;
  dropped = 0;
}

/** Runs one incoming message's handlers: a throw is reported, and the next message still runs. */
export function guardedDispatch(type: string, dispatch: () => void) {
  try {
    dispatch();
  } catch (error) {
    console.error(`handler for "${type}" failed`, error);
    reportUiError({ kind: 'handler', name: type, error, outcome: 'continued' });
  }
}

/** Reports every uncaught script error and rejection; the page's existing handler still runs after it. */
export function installErrorReporting(name: string) {
  const previous = window.onerror;
  window.onerror = (message, url, line, column, error) => {
    reportUiError({
      kind: 'script',
      name,
      error: error ?? `${message} at ${url}:${line}:${column}`,
      outcome: Byond.strictMode ? 'error-screen' : 'continued',
    });
    return previous ? previous(message, url, line, column, error) : false;
  };
}
