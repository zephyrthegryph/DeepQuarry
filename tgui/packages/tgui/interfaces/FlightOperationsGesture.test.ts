import { describe, expect, test } from 'bun:test';
import {
  beginFlightDrag,
  FLIGHT_DRAG_THRESHOLD,
  updateFlightDrag,
} from './FlightOperationsGesture';

describe('flight camera drag gestures', () => {
  test('a stationary press remains a click', () => {
    const update = updateFlightDrag(beginFlightDrag(0, 50, 60), 52, 61);

    expect(update.state.moved).toBe(false);
    expect(update.state.axis).toBeUndefined();
  });

  test('vertical drag locks from total pointer-down displacement', () => {
    let state = beginFlightDrag(0, 100, 100);
    state = updateFlightDrag(state, 102, 101).state;
    const update = updateFlightDrag(
      state,
      102,
      100 + FLIGHT_DRAG_THRESHOLD + 4,
    );

    expect(update.state.moved).toBe(true);
    expect(update.state.axis).toBe('vertical');
    expect(update.dy).toBe(FLIGHT_DRAG_THRESHOLD + 4);
  });

  test('a locked vertical drag ignores minor horizontal pointer noise', () => {
    let update = updateFlightDrag(beginFlightDrag(0, 10, 10), 10, 20);
    update = updateFlightDrag(update.state, 15, 24);

    expect(update.state.axis).toBe('vertical');
    expect(update.dy).toBe(4);
  });

  test('horizontal intent recovers from an initial vertical lock', () => {
    let update = updateFlightDrag(beginFlightDrag(0, 10, 10), 10, 15);
    update = updateFlightDrag(update.state, 40, 16);

    expect(update.state.axis).toBe('horizontal');
    expect(update.dx).toBe(30);
  });

  test('right-button panning retains both axes', () => {
    const update = updateFlightDrag(beginFlightDrag(2, 5, 5), 12, 14);

    expect(update.dx).toBe(7);
    expect(update.dy).toBe(9);
  });
});
