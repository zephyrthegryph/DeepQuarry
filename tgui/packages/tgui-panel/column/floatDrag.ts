/**
 * A drag that left the column while the button is still down: the window floated at the pointer and keeps following it from the
 * column page (which holds the pointer) until release. The native window's page cannot take the button over, so the column page
 * moves it with winset, by the window id the new window reports (wm/floated). Pure placement lives in tgui/floatPlacement.ts.
 */
import { type Pair, placeUnder } from 'tgui/floatPlacement';

export type FloatSend = (id: string, props: { pos: string }) => void;
export type FloatLog = (
  message: string,
  detail?: Record<string, unknown>,
) => void;

export class FloatFollow {
  private windowId: string | null = null;
  private point: Pair;
  private sent = '';
  private released = false;
  private finished = false;

  constructor(
    /** The size the window opened at (physical px): its width centres it under the pointer. */
    private readonly size: Pair,
    start: Pair,
    private readonly send: FloatSend,
    private readonly log: FloatLog,
    /** Called once the window is released and placed, with its id. */
    private readonly done: (id: string) => void,
  ) {
    this.point = start;
  }

  /** The pointer moved (screen px). */
  move(point: Pair) {
    this.point = point;
    this.apply();
  }

  /** The new native window reported its id. */
  adopt(id: string) {
    if (this.windowId || this.finished) return;
    this.windowId = id;
    this.log('float follow: window adopted', { id, point: this.point });
    this.apply();
    if (this.released) this.finish();
  }

  /** The button went up at `point`. */
  release(point: Pair) {
    this.point = point;
    this.released = true;
    this.log('float follow: released', { point, waiting: !this.windowId });
    this.apply();
    if (this.windowId) this.finish();
  }

  get adopted() {
    return this.windowId !== null;
  }

  private apply() {
    if (!this.windowId) return;
    const pos = placeUnder(this.point, this.size[0]);
    const text = `${pos[0]},${pos[1]}`;
    if (text === this.sent) return;
    this.sent = text;
    this.send(this.windowId, { pos: text });
  }

  private finish() {
    const id = this.windowId;
    this.windowId = null;
    this.finished = true;
    if (id) this.done(id);
  }
}
