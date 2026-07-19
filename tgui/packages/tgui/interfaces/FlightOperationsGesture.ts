export type FlightDragAxis = 'horizontal' | 'vertical';

export type FlightDragState = {
  button: number;
  startX: number;
  startY: number;
  lastX: number;
  lastY: number;
  moved: boolean;
  axis?: FlightDragAxis;
};

export type FlightDragUpdate = {
  state: FlightDragState;
  dx: number;
  dy: number;
};

export const FLIGHT_DRAG_THRESHOLD = 4;
const FLIGHT_AXIS_SWITCH_RATIO = 1.5;

export const beginFlightDrag = (
  button: number,
  x: number,
  y: number,
): FlightDragState => ({
  button,
  startX: x,
  startY: y,
  lastX: x,
  lastY: y,
  moved: false,
});

/**
 * Reduces pointer positions into a stable drag gesture. Axis selection uses the
 * displacement from pointer-down, so event frequency and tiny initial jitter do
 * not change the gesture. The displacement accumulated before axis lock is
 * returned on the frame that the threshold is crossed.
 */
export const updateFlightDrag = (
  state: FlightDragState,
  x: number,
  y: number,
): FlightDragUpdate => {
  const totalX = x - state.startX;
  const totalY = y - state.startY;
  const moved =
    state.moved || Math.hypot(totalX, totalY) >= FLIGHT_DRAG_THRESHOLD;
  const horizontalDominates =
    Math.abs(totalX) > Math.abs(totalY) * FLIGHT_AXIS_SWITCH_RATIO;
  const verticalDominates =
    Math.abs(totalY) > Math.abs(totalX) * FLIGHT_AXIS_SWITCH_RATIO;
  let axis = state.axis;
  if (!axis && moved)
    axis = Math.abs(totalX) >= Math.abs(totalY) ? 'horizontal' : 'vertical';
  else if (axis === 'vertical' && horizontalDominates) axis = 'horizontal';
  else if (axis === 'horizontal' && verticalDominates) axis = 'vertical';
  const justLocked = !state.axis && !!axis;

  return {
    state: {
      ...state,
      lastX: x,
      lastY: y,
      moved,
      axis,
    },
    dx: justLocked ? totalX : x - state.lastX,
    dy: justLocked ? totalY : y - state.lastY,
  };
};
