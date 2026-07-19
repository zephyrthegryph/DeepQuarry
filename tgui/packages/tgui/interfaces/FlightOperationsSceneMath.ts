import type { FlightDestination } from './FlightOperations';

export type Vec3 = { x: number; y: number; z: number };

export const addVec3 = (a: Vec3, b: Vec3): Vec3 => ({
  x: a.x + b.x,
  y: a.y + b.y,
  z: a.z + b.z,
});

export const subtractVec3 = (a: Vec3, b: Vec3): Vec3 => ({
  x: a.x - b.x,
  y: a.y - b.y,
  z: a.z - b.z,
});

export const vec3Length = (a: Vec3) => Math.hypot(a.x, a.y, a.z);

export const orbitLocalPosition = (
  body: FlightDestination,
  epoch: number,
): Vec3 => {
  const angle =
    ((body.orbit_phase || 0) * Math.PI) / 180 +
    (epoch / Math.max(20, body.orbit_period)) * Math.PI * 2;
  const incline = ((body.orbit_inclination || 0) * Math.PI) / 180;
  return {
    x: Math.cos(angle) * body.orbit_radius,
    y: Math.sin(angle) * body.orbit_radius * Math.sin(incline),
    z: Math.sin(angle) * body.orbit_radius * Math.cos(incline),
  };
};

const dockedOffset = (
  body: FlightDestination,
  host: FlightDestination,
  bodies: FlightDestination[],
): Vec3 => {
  const siblings = bodies.filter(
    (candidate) => candidate.docked_host_id === host.id,
  );
  const index = Math.max(
    0,
    siblings.findIndex((candidate) => candidate.id === body.id),
  );
  const angle = index * 2.399 + 0.55;
  const separation = Math.max(
    5,
    host.body_radius * 2.8 + body.body_radius * 2 + index * 1.5,
  );
  return {
    x: Math.cos(angle) * separation,
    y: (index % 2 ? 1 : -1) * separation * 0.22,
    z: Math.sin(angle) * separation,
  };
};

/** Resolve authoritative scene transforms without inferring roles from names. */
export const resolveScenePositions = (
  bodies: FlightDestination[],
  epoch: number,
): Map<string, Vec3> => {
  const byId = new Map(bodies.map((body) => [body.id, body]));
  const positions = new Map<string, Vec3>();
  const resolving = new Set<string>();
  const resolve = (body: FlightDestination): Vec3 => {
    const cached = positions.get(body.id);
    if (cached) return cached;
    if (resolving.has(body.id)) return { x: 0, y: 0, z: 0 };
    resolving.add(body.id);
    const parent = body.orbit_parent_id && byId.get(body.orbit_parent_id);
    const host = body.docked_host_id && byId.get(body.docked_host_id);
    let result: Vec3 = { x: 0, y: 0, z: 0 };
    if (body.scene_role === 'docked' && host)
      result = addVec3(resolve(host), dockedOffset(body, host, bodies));
    else if (parent)
      result = addVec3(resolve(parent), orbitLocalPosition(body, epoch));
    positions.set(body.id, result);
    resolving.delete(body.id);
    return result;
  };
  bodies.filter((body) => body.kind !== 'expedition').forEach(resolve);
  return positions;
};

export const resolveOrbitPath = (
  body: FlightDestination,
  bodies: FlightDestination[],
  epoch: number,
  samples = 80,
): Vec3[] => {
  if (!body.orbit_parent_id || body.scene_role === 'docked') return [];
  const center = resolveScenePositions(bodies, epoch).get(body.orbit_parent_id);
  if (!center) return [];
  return Array.from({ length: samples + 1 }, (_, sample) =>
    addVec3(
      center,
      orbitLocalPosition(
        body,
        epoch + (sample / samples) * body.orbit_period,
      ),
    ),
  );
};
