import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { fireEvent, render } from '@testing-library/react';
import type { FlightDestination } from './FlightOperations';
import { WebGLCelestialScene } from './FlightOperationsScene';

const body: FlightDestination = {
  id: 'system-vir',
  name: 'Vir',
  description: 'Star',
  kind: 'system',
  scene_role: 'celestial',
  orbit_radius: 0,
  orbit_period: 1,
  orbit_phase: 0,
  orbit_inclination: 0,
  body_radius: 12,
  body_color: '#ffffff',
  compatible: 1,
  materialized: 1,
  is_current: 0,
};

describe('mounted flight scene input', () => {
  let originalGetContext: typeof HTMLCanvasElement.prototype.getContext;
  let originalClientWidth: PropertyDescriptor | undefined;
  let originalClientHeight: PropertyDescriptor | undefined;
  let originalBounds: typeof HTMLCanvasElement.prototype.getBoundingClientRect;

  beforeAll(() => {
    originalGetContext = HTMLCanvasElement.prototype.getContext;
    originalClientWidth = Object.getOwnPropertyDescriptor(
      HTMLElement.prototype,
      'clientWidth',
    );
    originalClientHeight = Object.getOwnPropertyDescriptor(
      HTMLElement.prototype,
      'clientHeight',
    );
    originalBounds = HTMLCanvasElement.prototype.getBoundingClientRect;
    Object.defineProperty(HTMLElement.prototype, 'clientWidth', {
      configurable: true,
      get: () => 800,
    });
    Object.defineProperty(HTMLElement.prototype, 'clientHeight', {
      configurable: true,
      get: () => 600,
    });
    HTMLCanvasElement.prototype.getBoundingClientRect = () =>
      ({ left: 0, top: 0, width: 800, height: 600 }) as DOMRect;
    HTMLCanvasElement.prototype.getContext = ((kind: string) => {
      if (kind === '2d') {
        return new Proxy(
          { measureText: () => ({ width: 20 }) },
          { get: (target, key) => target[key] || (() => undefined) },
        ) as never;
      }
      return new Proxy(
        {},
        {
          get: (_target, key) => {
            if (key === 'getShaderParameter' || key === 'getProgramParameter')
              return () => true;
            if (
              key === 'createShader' ||
              key === 'createProgram' ||
              key === 'createBuffer'
            )
              return () => ({});
            if (key === 'getAttribLocation') return () => 0;
            if (key === 'getUniformLocation') return () => ({});
            if (typeof key === 'string' && key.toUpperCase() === key) return 1;
            return () => undefined;
          },
        },
      ) as never;
    }) as typeof HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.setPointerCapture = () => undefined;
    HTMLCanvasElement.prototype.releasePointerCapture = () => undefined;
    HTMLCanvasElement.prototype.hasPointerCapture = () => false;
    globalThis.requestAnimationFrame = () => 1;
    globalThis.cancelAnimationFrame = () => undefined;
  });

  afterAll(() => {
    HTMLCanvasElement.prototype.getContext = originalGetContext;
    HTMLCanvasElement.prototype.getBoundingClientRect = originalBounds;
    if (originalClientWidth)
      Object.defineProperty(
        HTMLElement.prototype,
        'clientWidth',
        originalClientWidth,
      );
    if (originalClientHeight)
      Object.defineProperty(
        HTMLElement.prototype,
        'clientHeight',
        originalClientHeight,
      );
  });

  test('server update does not tear down a drag that began over a rendered target', () => {
    let selections = 0;
    const base = {
      bodies: [body],
      focusId: body.id,
      selectedId: undefined,
      vesselDestinationId: undefined,
      plan: undefined,
      onFocus: () => undefined,
      onSelect: () => selections++,
    };
    const view = render(<WebGLCelestialScene {...base} serverTime={100} />);
    const canvas = view.container.querySelector('canvas')!;

    // Vir is projected at the canvas center. Confirm this coordinate is a real
    // rendered hit before using the same point as the drag origin.
    fireEvent.pointerDown(canvas, {
      button: 0,
      clientX: 400,
      clientY: 300,
      pointerId: 6,
    });
    fireEvent.pointerUp(window, {
      button: 0,
      clientX: 400,
      clientY: 300,
      pointerId: 6,
    });
    expect(selections).toBe(1);
    selections = 0;

    fireEvent.pointerDown(canvas, {
      button: 0,
      clientX: 400,
      clientY: 300,
      pointerId: 7,
    });
    view.rerender(<WebGLCelestialScene {...base} serverTime={101} />);
    fireEvent.pointerMove(window, {
      button: 0,
      clientX: 400,
      clientY: 320,
      pointerId: 7,
    });
    fireEvent.pointerUp(window, {
      button: 0,
      clientX: 400,
      clientY: 320,
      pointerId: 7,
    });

    expect(Number(canvas.dataset.cameraPitch)).toBeCloseTo(0.26);
    expect(Number(canvas.dataset.cameraYaw)).toBeCloseTo(-0.7);
    expect(selections).toBe(0);

    fireEvent.pointerDown(canvas, {
      button: 0,
      clientX: 400,
      clientY: 300,
      pointerId: 8,
    });
    fireEvent.pointerMove(window, {
      button: 0,
      clientX: 420,
      clientY: 300,
      pointerId: 8,
    });
    fireEvent.pointerUp(window, {
      button: 0,
      clientX: 420,
      clientY: 300,
      pointerId: 8,
    });

    expect(Number(canvas.dataset.cameraPitch)).toBeCloseTo(0.26);
    expect(Number(canvas.dataset.cameraYaw)).toBeCloseTo(-0.8);
    expect(selections).toBe(0);

    fireEvent.pointerDown(canvas, {
      button: 0,
      clientX: 400,
      clientY: 300,
      pointerId: 9,
    });
    fireEvent.pointerMove(window, {
      button: 0,
      clientX: 400,
      clientY: 305,
      pointerId: 9,
    });
    fireEvent.pointerMove(window, {
      button: 0,
      clientX: 430,
      clientY: 306,
      pointerId: 9,
    });
    fireEvent.pointerUp(window, {
      button: 0,
      clientX: 430,
      clientY: 306,
      pointerId: 9,
    });

    expect(Number(canvas.dataset.cameraYaw)).toBeCloseTo(-0.95);
    expect(selections).toBe(0);
  });
});
