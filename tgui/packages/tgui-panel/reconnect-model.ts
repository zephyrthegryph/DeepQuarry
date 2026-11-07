/** Delays before each reconnect attempt, in ms; the last one repeats. */
export const RECONNECT_DELAYS = [2000, 5000, 10000, 15000];

/** Delay before attempt number `attempt` (1-based). */
export function reconnectDelay(attempt: number): number {
  const i = Math.max(0, Math.min(attempt - 1, RECONNECT_DELAYS.length - 1));
  return RECONNECT_DELAYS[i];
}

export type ReconnectState = {
  active: boolean;
  /** Attempts made so far. */
  attempt: number;
  /** When the next attempt fires (ms epoch), or null. */
  nextAt: number | null;
  cancelled: boolean;
};

export type ReconnectDeps = {
  now: () => number;
  setTimer: (fn: () => void, ms: number) => unknown;
  clearTimer: (id: unknown) => void;
  /** Issues the actual reconnect (`.reconnect`). */
  reconnect: () => void;
  log: (message: string) => void;
  onChange: (state: ReconnectState) => void;
};

const IDLE: ReconnectState = {
  active: false,
  attempt: 0,
  nextAt: null,
  cancelled: false,
};

/**
 * Drives automatic reconnects with backoff. Call setDown(true) while the
 * connection is lost (ping timeout or round restart), setDown(false) once it is
 * back. cancel() stops until the connection has come back once.
 */
export class Reconnector {
  private state: ReconnectState = IDLE;
  private timer: unknown = null;

  constructor(private deps: ReconnectDeps) {}

  getState(): ReconnectState {
    return this.state;
  }

  setDown(down: boolean): void {
    if (!down) {
      if (this.state.active || this.state.cancelled) {
        this.deps.log(
          `connection restored after ${this.state.attempt} attempt(s)`,
        );
      }
      this.stopTimer();
      if (this.state !== IDLE) this.update(IDLE);
      return;
    }
    if (this.state.active || this.state.cancelled) return;
    this.deps.log('connection lost, starting automatic reconnect');
    this.update({ ...IDLE, active: true });
    this.schedule();
  }

  cancel(): void {
    this.deps.log('automatic reconnect cancelled by user');
    this.stopTimer();
    this.update({
      active: false,
      attempt: this.state.attempt,
      nextAt: null,
      cancelled: true,
    });
  }

  private schedule(): void {
    const delay = reconnectDelay(this.state.attempt + 1);
    this.update({ ...this.state, nextAt: this.deps.now() + delay });
    this.timer = this.deps.setTimer(() => this.fire(), delay);
  }

  private fire(): void {
    this.timer = null;
    if (!this.state.active) return;
    const attempt = this.state.attempt + 1;
    this.update({ ...this.state, attempt, nextAt: null });
    this.deps.log(`reconnect attempt ${attempt}`);
    this.deps.reconnect();
    this.schedule();
  }

  private stopTimer(): void {
    if (this.timer !== null) {
      this.deps.clearTimer(this.timer);
      this.timer = null;
    }
  }

  private update(next: ReconnectState): void {
    this.state = next;
    this.deps.onChange(next);
  }
}
