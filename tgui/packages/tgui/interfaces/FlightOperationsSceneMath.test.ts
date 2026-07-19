import { describe, expect, test } from 'bun:test';
import type { FlightDestination } from './FlightOperations';
import {
  resolveOrbitPath,
  resolveScenePositions,
  subtractVec3,
  vec3Length,
} from './FlightOperationsSceneMath';

const body = (
  id: string,
  overrides: Partial<FlightDestination> = {},
): FlightDestination => ({
  id,
  name: id,
  description: '',
  kind: 'vessel',
  orbit_radius: 0,
  orbit_period: 100,
  orbit_phase: 0,
  orbit_inclination: 0,
  body_radius: 1,
  body_color: '#ffffff',
  compatible: 1,
  materialized: 1,
  is_current: 0,
  ...overrides,
});

describe('flight scene hierarchy', () => {
  const vir = body('vir', { kind: 'system', body_radius: 5 });
  const sif = body('sif', {
    kind: 'surface',
    orbit_parent_id: 'vir',
    orbit_radius: 64,
    orbit_period: 1200,
  });
  const carrier = body('carrier', {
    scene_role: 'orbital',
    orbit_parent_id: 'sif',
    docked_host_id: 'station',
    orbit_radius: 19,
    orbit_period: 600,
  });
  const station = body('station', {
    kind: 'station',
    orbit_parent_id: 'sif',
    orbit_radius: 13,
  });
  const mammoth = body('baby_mammoth', {
    scene_role: 'docked',
    docked_host_id: 'carrier',
  });
  const ursula = body('ursula', {
    scene_role: 'docked',
    docked_host_id: 'carrier',
  });
  const bodies = [vir, sif, carrier, station, mammoth, ursula];

  test.each([0, 125, 800])(
    'carrier remains exactly on its Sif-relative orbit at epoch %d',
    (epoch) => {
      const positions = resolveScenePositions(bodies, epoch);
      const relative = subtractVec3(
        positions.get('carrier')!,
        positions.get('sif')!,
      );
      expect(vec3Length(relative)).toBeCloseTo(19, 8);
    },
  );

  test.each([0, 125, 800])(
    'carrier orbit ring is centered on moving Sif at epoch %d',
    (epoch) => {
      const positions = resolveScenePositions(bodies, epoch);
      const center = positions.get('sif')!;
      const orbit = resolveOrbitPath(carrier, bodies, epoch);
      for (const point of orbit)
        expect(vec3Length(subtractVec3(point, center))).toBeCloseTo(19, 8);
    },
  );

  test.each([0, 125, 800])(
    'docked vessels remain in a distinct compact formation around the carrier at epoch %d',
    (epoch) => {
      const positions = resolveScenePositions(bodies, epoch);
      const carrierPosition = positions.get('carrier')!;
      const mammothPosition = positions.get('baby_mammoth')!;
      const ursulaPosition = positions.get('ursula')!;
      expect(vec3Length(subtractVec3(mammothPosition, carrierPosition))).toBeLessThan(12);
      expect(vec3Length(subtractVec3(ursulaPosition, carrierPosition))).toBeLessThan(12);
      expect(vec3Length(subtractVec3(mammothPosition, ursulaPosition))).toBeGreaterThan(1);
    },
  );
});
