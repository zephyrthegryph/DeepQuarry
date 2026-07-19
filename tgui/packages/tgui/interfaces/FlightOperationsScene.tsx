import { useEffect, useRef } from 'react';
import type { FlightDestination, FlightPlan } from './FlightOperations';
import {
  beginFlightDrag,
  type FlightDragState,
  updateFlightDrag,
} from './FlightOperationsGesture';
import {
  resolveOrbitPath,
  resolveScenePositions,
} from './FlightOperationsSceneMath';

type Vec3 = { x: number; y: number; z: number };
type Camera = { target: Vec3; yaw: number; pitch: number; distance: number };
type Projection = { x: number; y: number; depth: number; visible: boolean };
type Hit = {
  body: FlightDestination;
  x: number;
  y: number;
  radius: number;
  depth: number;
};

const add = (a: Vec3, b: Vec3): Vec3 => ({
  x: a.x + b.x,
  y: a.y + b.y,
  z: a.z + b.z,
});
const sub = (a: Vec3, b: Vec3): Vec3 => ({
  x: a.x - b.x,
  y: a.y - b.y,
  z: a.z - b.z,
});
const mul = (a: Vec3, scalar: number): Vec3 => ({
  x: a.x * scalar,
  y: a.y * scalar,
  z: a.z * scalar,
});
const length = (a: Vec3) => Math.hypot(a.x, a.y, a.z);
const normalize = (a: Vec3) => mul(a, 1 / Math.max(0.00001, length(a)));
const cross = (a: Vec3, b: Vec3): Vec3 => ({
  x: a.y * b.z - a.z * b.y,
  y: a.z * b.x - a.x * b.z,
  z: a.x * b.y - a.y * b.x,
});
const dot = (a: Vec3, b: Vec3) => a.x * b.x + a.y * b.y + a.z * b.z;
const mix = (a: number, b: number, t: number) => a + (b - a) * t;
const mixVec = (a: Vec3, b: Vec3, t: number): Vec3 => ({
  x: mix(a.x, b.x, t),
  y: mix(a.y, b.y, t),
  z: mix(a.z, b.z, t),
});
const ease = (value: number) => value * value * (3 - 2 * value);

const hash = (value: string) => {
  let result = 2166136261;
  for (let index = 0; index < value.length; index++)
    result = Math.imul(result ^ value.charCodeAt(index), 16777619);
  return result >>> 0;
};

const color = (value: string): [number, number, number] => {
  const match = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(value);
  return match
    ? [
        Number.parseInt(match[1], 16) / 255,
        Number.parseInt(match[2], 16) / 255,
        Number.parseInt(match[3], 16) / 255,
      ]
    : [0.4, 0.7, 0.9];
};

const compile = (gl: WebGLRenderingContext, type: number, source: string) => {
  const shader = gl.createShader(type)!;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS))
    throw new Error(gl.getShaderInfoLog(shader) || 'Flight shader failed');
  return shader;
};

const program = (
  gl: WebGLRenderingContext,
  vertex: string,
  fragment: string,
) => {
  const result = gl.createProgram()!;
  gl.attachShader(result, compile(gl, gl.VERTEX_SHADER, vertex));
  gl.attachShader(result, compile(gl, gl.FRAGMENT_SHADER, fragment));
  gl.linkProgram(result);
  if (!gl.getProgramParameter(result, gl.LINK_STATUS))
    throw new Error(gl.getProgramInfoLog(result) || 'Flight program failed');
  return result;
};

const sphere = () => {
  const vertices: number[] = [];
  const indices: number[] = [];
  const rows = 24;
  const columns = 36;
  for (let row = 0; row <= rows; row++) {
    const latitude = (row / rows) * Math.PI;
    for (let column = 0; column <= columns; column++) {
      const longitude = (column / columns) * Math.PI * 2;
      vertices.push(
        Math.sin(latitude) * Math.cos(longitude),
        Math.cos(latitude),
        Math.sin(latitude) * Math.sin(longitude),
      );
    }
  }
  for (let row = 0; row < rows; row++)
    for (let column = 0; column < columns; column++) {
      const first = row * (columns + 1) + column;
      indices.push(
        first,
        first + columns + 1,
        first + 1,
        first + 1,
        first + columns + 1,
        first + columns + 2,
      );
    }
  return {
    vertices: new Float32Array(vertices),
    indices: new Uint16Array(indices),
  };
};

const matrix = (eye: Vec3, target: Vec3, aspect: number) => {
  const forward = normalize(sub(target, eye));
  const right = normalize(cross(forward, { x: 0, y: 1, z: 0 }));
  const up = cross(right, forward);
  const near = 0.1;
  const far = 4000;
  const f = 1 / Math.tan((42 * Math.PI) / 360);
  const view = new Float32Array([
    right.x,
    up.x,
    -forward.x,
    0,
    right.y,
    up.y,
    -forward.y,
    0,
    right.z,
    up.z,
    -forward.z,
    0,
    -dot(right, eye),
    -dot(up, eye),
    dot(forward, eye),
    1,
  ]);
  const projection = new Float32Array([
    f / aspect,
    0,
    0,
    0,
    0,
    f,
    0,
    0,
    0,
    0,
    (far + near) / (near - far),
    -1,
    0,
    0,
    (2 * far * near) / (near - far),
    0,
  ]);
  const out = new Float32Array(16);
  for (let column = 0; column < 4; column++)
    for (let row = 0; row < 4; row++) {
      out[column * 4 + row] =
        projection[row] * view[column * 4] +
        projection[4 + row] * view[column * 4 + 1] +
        projection[8 + row] * view[column * 4 + 2] +
        projection[12 + row] * view[column * 4 + 3];
    }
  return { matrix: out, eye, right, up, forward, f };
};

const shaderVertex = `
attribute vec3 aPosition;
uniform mat4 uViewProjection;
uniform vec4 uBody;
uniform float uRotation;
varying vec3 vNormal;
varying vec3 vLocal;
void main() {
  float c = cos(uRotation), s = sin(uRotation);
  vec3 local = vec3(aPosition.x*c-aPosition.z*s, aPosition.y, aPosition.x*s+aPosition.z*c);
  vLocal = local;
  vNormal = local;
  gl_Position = uViewProjection * vec4(uBody.xyz + local * uBody.w, 1.0);
}`;

const shaderFragment = `
precision mediump float;
uniform vec3 uColor;
uniform float uSeed;
uniform float uKind;
uniform vec3 uEye;
varying vec3 vNormal;
varying vec3 vLocal;
float hashNoise(vec3 p) {
  p = fract(p * .1031); p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}
float noise(vec3 p) {
  vec3 cell = floor(p);
  vec3 part = fract(p);
  part = part * part * (3.0 - 2.0 * part);
  return mix(
    mix(mix(hashNoise(cell), hashNoise(cell + vec3(1.,0.,0.)), part.x),
        mix(hashNoise(cell + vec3(0.,1.,0.)), hashNoise(cell + vec3(1.,1.,0.)), part.x), part.y),
    mix(mix(hashNoise(cell + vec3(0.,0.,1.)), hashNoise(cell + vec3(1.,0.,1.)), part.x),
        mix(hashNoise(cell + vec3(0.,1.,1.)), hashNoise(cell + vec3(1.,1.,1.)), part.x), part.y), part.z);
}
float terrain(vec3 p) {
  vec3 offset = vec3(uSeed, uSeed * .37, uSeed * .71);
  // Domain warping breaks up the round value-noise islands. The broad octave
  // establishes continents while the two finer octaves only texture coasts.
  vec3 warp = vec3(
    noise(p * 2.1 + offset),
    noise(p * 2.1 + offset + 19.7),
    noise(p * 2.1 + offset + 43.1)
  ) - .5;
  vec3 q = p + warp * .22;
  float broad = noise(q * 2.45 + offset);
  float ridges = 1.0 - abs(noise(q * 5.2 + offset * 1.7) * 2.0 - 1.0);
  float detail = noise(q * 12.0 + offset * 2.3);
  return broad * .68 + ridges * .20 + detail * .12;
}
float cloudField(vec3 p) {
  vec3 offset = vec3(uSeed * .13, uSeed * .071, uSeed * .037);
  vec3 wind = vec3(.21, .04, -.13);
  float broad = noise(p * 3.2 + offset + wind);
  float wisps = noise(p * 7.5 + offset * 1.9 + wind * 2.0);
  float fine = noise(p * 15.0 + offset * 3.1);
  return broad * .58 + wisps * .29 + fine * .13;
}
void main() {
  vec3 n = normalize(vNormal);
  float light = max(.08, dot(n, normalize(vec3(-.7,.5,.9))));
  if (uKind < .5) {
    float flare = pow(max(0.0, dot(n, normalize(uEye))), 2.0);
    gl_FragColor = vec4(uColor * (1.15 + light*.6) + flare*.35, 1.0);
    return;
  }
  float h = terrain(vLocal);
  vec3 ocean = uColor * vec3(.32,.58,.72);
  vec3 lowland = mix(uColor * .65, vec3(.18,.42,.23), .55);
  vec3 highland = mix(lowland, vec3(.72,.69,.54), smoothstep(.60,.82,h));
  vec3 ground = mix(ocean, highland, smoothstep(.47,.51,h));
  float ice = smoothstep(.72,.94,abs(vLocal.y));
  ground = mix(ground, vec3(.82,.91,.94), ice*.7);
  float cloudDensity = cloudField(vLocal);
  float clouds = smoothstep(.57, .74, cloudDensity);
  float cloudSoftness = smoothstep(.48, .68, cloudDensity);
  vec3 cloudColor = mix(vec3(.72,.79,.84), vec3(.97,.98,1.), light);
  ground = mix(ground, cloudColor, clouds * cloudSoftness * .52);
  float rim = pow(1.0-max(0.0,dot(n,normalize(uEye))),3.0);
  gl_FragColor = vec4(ground*(.22+light*.9)+vec3(.18,.42,.65)*rim*.45,1.0);
}`;

const lineVertex = `attribute vec3 aPosition; uniform mat4 uViewProjection; uniform float uPointSize; void main(){ gl_Position=uViewProjection*vec4(aPosition,1.0); gl_PointSize=uPointSize; }`;
const lineFragment = `precision mediump float; uniform vec4 uColor; void main(){ gl_FragColor=uColor; }`;

type CelestialSceneProps = {
  bodies: FlightDestination[];
  focusId: string;
  selectedId?: string;
  vesselDestinationId?: string;
  plan?: FlightPlan;
  serverTime: number;
  onFocus: (id: string) => void;
  onSelect: (id: string) => void;
};

export const WebGLCelestialScene = (initialProps: CelestialSceneProps) => {
  // BYOND republishes serverTime (and usually fresh array/object identities) on
  // every UI update. Keep the mounted WebGL scene and its active pointer
  // capture alive while making each animation frame observe the newest data.
  const latest = useRef({ props: initialProps, receivedAt: Date.now() });
  latest.current = { props: initialProps, receivedAt: Date.now() };
  const container = useRef<HTMLDivElement>(null);
  const webgl = useRef<HTMLCanvasElement>(null);
  const overlay = useRef<HTMLCanvasElement>(null);
  const camera = useRef<Camera>({
    target: { x: 0, y: 0, z: 0 },
    yaw: -0.7,
    pitch: 0.16,
    distance: 320,
  });
  const panOffset = useRef<Vec3>({ x: 0, y: 0, z: 0 });
  const trajectoryOrigin = useRef<
    { planId: string; position: Vec3 } | undefined
  >(undefined);
  const transition = useRef<
    | {
        start: number;
        fromTarget: Vec3;
        toTarget: Vec3;
        fromDistance: number;
        toDistance: number;
      }
    | undefined
  >(undefined);
  const previousFocus = useRef(initialProps.focusId);
  const drag = useRef<FlightDragState | undefined>(undefined);
  const hits = useRef<Hit[]>([]);

  useEffect(() => {
    const props = new Proxy(initialProps, {
      get: (_target, property: keyof CelestialSceneProps) =>
        latest.current.props[property],
    });
    const canvas = webgl.current;
    const labels = overlay.current;
    const gl = canvas?.getContext('webgl', { alpha: false, antialias: true });
    const context = labels?.getContext('2d');
    if (!canvas || !labels || !gl || !context) return;
    const planetProgram = program(gl, shaderVertex, shaderFragment);
    const simpleProgram = program(gl, lineVertex, lineFragment);
    const geometry = sphere();
    const sphereBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, sphereBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, geometry.vertices, gl.STATIC_DRAW);
    const indexBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, geometry.indices, gl.STATIC_DRAW);
    const dynamicBuffer = gl.createBuffer();
    let frame = 0;

    const render = () => {
      const byId = new Map(props.bodies.map((body) => [body.id, body]));
      const ratio = window.devicePixelRatio || 1;
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      if (canvas.width !== width * ratio || canvas.height !== height * ratio) {
        canvas.width = width * ratio;
        canvas.height = height * ratio;
        labels.width = width * ratio;
        labels.height = height * ratio;
      }
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.clearColor(0.004, 0.009, 0.02, 1);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      gl.enable(gl.DEPTH_TEST);
      context.setTransform(ratio, 0, 0, ratio, 0, 0);
      context.clearRect(0, 0, width, height);
      const elapsedSinceUpdate = (Date.now() - latest.current.receivedAt) / 100;
      const epoch = (props.serverTime + elapsedSinceUpdate) / 10;
      const positions = resolveScenePositions(props.bodies, epoch);
      const positionOf = (body: FlightDestination): Vec3 =>
        positions.get(body.id) || { x: 0, y: 0, z: 0 };

      if (props.plan && props.vesselDestinationId && props.plan.state <= 3) {
        const departurePosition = positions.get(props.vesselDestinationId);
        if (departurePosition) {
          trajectoryOrigin.current = {
            planId: props.plan.id,
            position: departurePosition,
          };
        }
      }
      if (
        props.plan &&
        props.plan.state >= 4 &&
        props.plan.state <= 7 &&
        props.vesselDestinationId
      ) {
        const start =
          trajectoryOrigin.current?.planId === props.plan.id
            ? trajectoryOrigin.current.position
            : positions.get(props.plan.origin_id || '');
        const end = positions.get(props.plan.destination_id);
        if (start && end) {
          const duration = Math.max(
            1,
            props.plan.arrival_at - props.plan.departure_at,
          );
          const now = props.serverTime + elapsedSinceUpdate;
          const transitProgress = Math.max(
            0,
            Math.min(1, (now - props.plan.departure_at) / duration),
          );
          const progress =
            props.plan.state === 4 || props.plan.state === 5
              ? transitProgress * 0.88
              : props.plan.state === 6
                ? 0.88 + transitProgress * 0.08
                : 0.98;
          const lift = Math.max(4, length(sub(end, start)) * 0.06);
          const control = add(mul(add(start, end), 0.5), {
            x: 0,
            y: lift,
            z: 0,
          });
          const inverse = 1 - progress;
          positions.set(
            props.vesselDestinationId,
            add(
              add(
                mul(start, inverse * inverse),
                mul(control, 2 * inverse * progress),
              ),
              mul(end, progress * progress),
            ),
          );
        }
      }

      const focus = byId.get(props.focusId);
      const focusPosition = focus
        ? positions.get(focus.id) || { x: 0, y: 0, z: 0 }
        : { x: 0, y: 0, z: 0 };
      if (previousFocus.current !== props.focusId) {
        previousFocus.current = props.focusId;
        panOffset.current = { x: 0, y: 0, z: 0 };
        transition.current = {
          start: Date.now(),
          fromTarget: camera.current.target,
          toTarget: focusPosition,
          fromDistance: camera.current.distance,
          toDistance:
            focus?.kind === 'surface'
              ? Math.max(28, focus.body_radius * 5.2)
              : 320,
        };
      }
      if (transition.current) {
        const elapsed = Math.min(
          1,
          (Date.now() - transition.current.start) / 1100,
        );
        const amount = ease(elapsed);
        camera.current.target = mixVec(
          transition.current.fromTarget,
          transition.current.toTarget,
          amount,
        );
        camera.current.distance = mix(
          transition.current.fromDistance,
          transition.current.toDistance,
          amount,
        );
        if (elapsed === 1) transition.current = undefined;
      } else camera.current.target = add(focusPosition, panOffset.current);
      const c = camera.current;
      const eye = add(c.target, {
        x: Math.sin(c.yaw) * Math.cos(c.pitch) * c.distance,
        y: Math.sin(c.pitch) * c.distance,
        z: Math.cos(c.yaw) * Math.cos(c.pitch) * c.distance,
      });
      const view = matrix(eye, c.target, Math.max(0.1, width / height));
      const projectPoint = (point: Vec3): Projection => {
        const relative = sub(point, eye);
        const depth = dot(relative, view.forward);
        if (depth <= 0.1) return { x: 0, y: 0, depth, visible: false };
        return {
          x:
            width * 0.5 +
            ((dot(relative, view.right) * view.f) / (width / height) / depth) *
              width *
              0.5,
          y:
            height * 0.5 -
            ((dot(relative, view.up) * view.f) / depth) * height * 0.5,
          depth,
          visible: true,
        };
      };

      const drawLines = (
        points: Vec3[],
        rgba: [number, number, number, number],
        mode: number = gl.LINE_STRIP,
        pointSize = 1,
      ) => {
        gl.useProgram(simpleProgram);
        gl.bindBuffer(gl.ARRAY_BUFFER, dynamicBuffer);
        gl.bufferData(
          gl.ARRAY_BUFFER,
          new Float32Array(
            points.flatMap((point) => [point.x, point.y, point.z]),
          ),
          gl.DYNAMIC_DRAW,
        );
        const attribute = gl.getAttribLocation(simpleProgram, 'aPosition');
        gl.enableVertexAttribArray(attribute);
        gl.vertexAttribPointer(attribute, 3, gl.FLOAT, false, 0, 0);
        gl.uniformMatrix4fv(
          gl.getUniformLocation(simpleProgram, 'uViewProjection'),
          false,
          view.matrix,
        );
        gl.uniform4fv(gl.getUniformLocation(simpleProgram, 'uColor'), rgba);
        gl.uniform1f(
          gl.getUniformLocation(simpleProgram, 'uPointSize'),
          pointSize * ratio,
        );
        gl.drawArrays(mode, 0, points.length);
      };

      for (const body of props.bodies) {
        if (body.kind === 'expedition') continue;
        const orbit = resolveOrbitPath(body, props.bodies, epoch);
        if (!orbit.length) continue;
        drawLines(
          orbit,
          body.kind === 'vessel'
            ? [0.25, 0.7, 0.9, 0.18]
            : [0.42, 0.55, 0.72, 0.3],
        );
      }
      if (props.plan && props.plan.state >= 4 && props.plan.state <= 7) {
        const start =
          trajectoryOrigin.current?.planId === props.plan.id
            ? trajectoryOrigin.current.position
            : positions.get(props.plan.origin_id || '');
        const end = positions.get(props.plan.destination_id);
        if (start && end) {
          const trajectory: Vec3[] = [];
          const control = add(mul(add(start, end), 0.5), {
            x: 0,
            y: Math.max(4, length(sub(end, start)) * 0.06),
            z: 0,
          });
          for (let index = 0; index <= 50; index++) {
            const t = index / 50;
            trajectory.push(
              add(
                add(
                  mul(start, (1 - t) * (1 - t)),
                  mul(control, 2 * (1 - t) * t),
                ),
                mul(end, t * t),
              ),
            );
          }
          drawLines(trajectory, [0.32, 1, 0.65, 0.72]);
        }
      }

      const drawSphere = (body: FlightDestination, position: Vec3) => {
        gl.useProgram(planetProgram);
        gl.bindBuffer(gl.ARRAY_BUFFER, sphereBuffer);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
        const attribute = gl.getAttribLocation(planetProgram, 'aPosition');
        gl.enableVertexAttribArray(attribute);
        gl.vertexAttribPointer(attribute, 3, gl.FLOAT, false, 0, 0);
        gl.uniformMatrix4fv(
          gl.getUniformLocation(planetProgram, 'uViewProjection'),
          false,
          view.matrix,
        );
        gl.uniform4f(
          gl.getUniformLocation(planetProgram, 'uBody'),
          position.x,
          position.y,
          position.z,
          Math.max(2, body.body_radius),
        );
        gl.uniform3fv(
          gl.getUniformLocation(planetProgram, 'uColor'),
          color(body.body_color),
        );
        gl.uniform1f(
          gl.getUniformLocation(planetProgram, 'uSeed'),
          (hash(body.id) % 10000) / 97,
        );
        gl.uniform1f(
          gl.getUniformLocation(planetProgram, 'uKind'),
          body.kind === 'system' ? 0 : 1,
        );
        gl.uniform3f(
          gl.getUniformLocation(planetProgram, 'uEye'),
          eye.x - position.x,
          eye.y - position.y,
          eye.z - position.z,
        );
        gl.uniform1f(
          gl.getUniformLocation(planetProgram, 'uRotation'),
          epoch * (body.kind === 'system' ? 0.004 : 0.012),
        );
        gl.drawElements(
          gl.TRIANGLES,
          geometry.indices.length,
          gl.UNSIGNED_SHORT,
          0,
        );
      };
      const ordered = props.bodies
        .filter((body) => body.kind !== 'expedition')
        .sort(
          (a, b) =>
            length(sub(positionOf(b), eye)) - length(sub(positionOf(a), eye)),
        );
      for (const body of ordered) {
        const dockedHost = body.docked_host_id && byId.get(body.docked_host_id);
        const position = positionOf(body);
        if (dockedHost) {
          drawLines(
            [positionOf(dockedHost), position],
            [0.32, 0.62, 0.72, 0.55],
          );
        }
        if (body.kind === 'system' || body.kind === 'surface')
          drawSphere(body, position);
        else {
          const scale = Math.max(2.4, body.body_radius);
          const points =
            body.kind === 'vessel'
              ? [
                  add(position, { x: scale * 1.5, y: 0, z: 0 }),
                  add(position, { x: -scale, y: scale * 0.75, z: 0 }),
                  add(position, { x: -scale * 0.4, y: 0, z: scale * 0.55 }),
                  add(position, { x: -scale, y: -scale * 0.75, z: 0 }),
                  add(position, { x: scale * 1.5, y: 0, z: 0 }),
                ]
              : [
                  add(position, { x: 0, y: scale * 1.2, z: 0 }),
                  add(position, { x: scale, y: 0, z: 0 }),
                  add(position, { x: 0, y: -scale * 1.2, z: 0 }),
                  add(position, { x: -scale, y: 0, z: 0 }),
                  add(position, { x: 0, y: scale * 1.2, z: 0 }),
                ];
          drawLines(
            points,
            body.kind === 'vessel' ? [0.52, 0.92, 1, 1] : [0.95, 0.74, 0.3, 1],
          );
        }
      }

      const labelCandidates: Array<{
        body: FlightDestination;
        point: Projection;
        radius: number;
        priority: number;
      }> = [];
      hits.current = [];
      for (const body of ordered) {
        const dockedHost = body.docked_host_id && byId.get(body.docked_host_id);
        const point = projectPoint(positionOf(body));
        if (!point.visible) continue;
        const pixelRadius = Math.max(
          6,
          (body.body_radius * view.f * height * 0.5) / point.depth,
        );
        hits.current.push({
          body,
          x: point.x,
          y: point.y,
          radius: Math.max(10, pixelRadius),
          depth: point.depth,
        });
        const selected = body.id === props.selectedId;
        const current = !!body.is_current;
        const focused = body.id === props.focusId;
        const threshold =
          focus?.kind === 'system' &&
          body.orbit_parent_id !== focus.id &&
          !selected &&
          !current
            ? 130
            : 500;
        const showDockedLabel =
          !dockedHost ||
          selected ||
          current ||
          focused ||
          props.focusId === dockedHost.id;
        if (
          showDockedLabel &&
          (point.depth < threshold || selected || current || focused)
        )
          labelCandidates.push({
            body,
            point,
            radius: pixelRadius,
            priority: current ? 4 : selected ? 3 : focused ? 2 : 1,
          });
      }
      if (focus?.kind === 'surface') {
        const planetPosition = positionOf(focus);
        const rotation = epoch * 0.012;
        for (const site of props.bodies.filter(
          (body) =>
            body.kind === 'expedition' && body.orbit_parent_id === focus.id,
        )) {
          const latitude = ((site.latitude || 0) * Math.PI) / 180;
          const longitude = ((site.longitude || 0) * Math.PI) / 180 + rotation;
          const normal = {
            x: Math.cos(latitude) * Math.cos(longitude),
            y: Math.sin(latitude),
            z: Math.cos(latitude) * Math.sin(longitude),
          };
          if (dot(normal, normalize(sub(eye, planetPosition))) <= 0) continue;
          const sitePosition = add(
            planetPosition,
            mul(normal, focus.body_radius * 1.035),
          );
          const point = projectPoint(sitePosition);
          drawLines(
            [sitePosition],
            [1, 0.72, 0.24, 1],
            gl.POINTS,
            site.id === props.selectedId ? 10 : 7,
          );
          hits.current.push({
            body: site,
            x: point.x,
            y: point.y,
            radius: 12,
            depth: point.depth,
          });
          labelCandidates.push({
            body: site,
            point,
            radius: 5,
            priority: site.id === props.selectedId ? 3 : 2,
          });
        }
      }
      const occupied: Array<{
        left: number;
        top: number;
        right: number;
        bottom: number;
      }> = [];
      for (const item of labelCandidates.sort(
        (a, b) => b.priority - a.priority || a.point.depth - b.point.depth,
      )) {
        const suffix = item.body.is_current ? ' — YOU' : '';
        context.font =
          item.priority >= 3 ? 'bold 12px sans-serif' : '12px sans-serif';
        const measured = context.measureText(item.body.name + suffix).width;
        const left = item.point.x + item.radius + 7;
        let top = item.point.y - 7;
        const rect = {
          left,
          top,
          right: left + measured + 6,
          bottom: top + 16,
        };
        let attempts = 0;
        while (
          occupied.some(
            (other) =>
              rect.left < other.right &&
              rect.right > other.left &&
              rect.top < other.bottom &&
              rect.bottom > other.top,
          ) &&
          attempts++ < 6
        ) {
          top += 17;
          rect.top = top;
          rect.bottom = top + 16;
        }
        if (attempts >= 6 && item.priority < 3) continue;
        occupied.push(rect);
        context.fillStyle = item.body.is_current ? '#58ffb0' : '#e3f1ff';
        context.shadowColor = '#000';
        context.shadowBlur = 4;
        context.fillText(item.body.name + suffix, left, top + 12);
        context.shadowBlur = 0;
      }
      frame = requestAnimationFrame(render);
    };

    const down = (event: PointerEvent) => {
      if (event.button !== 0 && event.button !== 2) return;
      event.preventDefault();
      drag.current = beginFlightDrag(
        event.button,
        event.clientX,
        event.clientY,
      );
      canvas.setPointerCapture(event.pointerId);
    };
    const move = (event: PointerEvent) => {
      if (!drag.current) return;
      const update = updateFlightDrag(
        drag.current,
        event.clientX,
        event.clientY,
      );
      drag.current = update.state;
      if (!drag.current.moved) return;
      const { dx, dy } = update;
      transition.current = undefined;
      if (drag.current.button === 2) {
        const scale = camera.current.distance * 0.0018;
        const yaw = camera.current.yaw;
        const pitch = camera.current.pitch;
        const right = { x: Math.cos(yaw), y: 0, z: -Math.sin(yaw) };
        const up = {
          x: -Math.sin(yaw) * Math.sin(pitch),
          y: Math.cos(pitch),
          z: -Math.cos(yaw) * Math.sin(pitch),
        };
        panOffset.current = add(
          panOffset.current,
          add(mul(right, -dx * scale), mul(up, dy * scale)),
        );
        camera.current.target = add(
          camera.current.target,
          add(mul(right, -dx * scale), mul(up, dy * scale)),
        );
      } else {
        if (drag.current.axis === 'horizontal')
          camera.current.yaw -= dx * 0.005;
        else if (drag.current.axis === 'vertical')
          camera.current.pitch = Math.max(
            -1.35,
            Math.min(1.35, camera.current.pitch + dy * 0.005),
          );
        canvas.dataset.cameraPitch = String(camera.current.pitch);
        canvas.dataset.cameraYaw = String(camera.current.yaw);
      }
    };
    const up = (event: PointerEvent) => {
      if (drag.current?.button === 0 && !drag.current.moved) {
        const bounds = canvas.getBoundingClientRect();
        const x = event.clientX - bounds.left;
        const y = event.clientY - bounds.top;
        const hit = [...hits.current]
          .sort((a, b) => a.depth - b.depth)
          .find(
            (candidate) =>
              Math.hypot(candidate.x - x, candidate.y - y) <= candidate.radius,
          );
        if (hit) {
          props.onSelect(hit.body.id);
          if (hit.body.kind === 'surface' || hit.body.kind === 'system')
            props.onFocus(hit.body.id);
        }
      }
      drag.current = undefined;
      if (canvas.hasPointerCapture(event.pointerId))
        canvas.releasePointerCapture(event.pointerId);
    };
    const cancel = () => {
      drag.current = undefined;
    };
    const contextMenu = (event: MouseEvent) => event.preventDefault();
    const wheel = (event: WheelEvent) => {
      event.preventDefault();
      transition.current = undefined;
      camera.current.distance = Math.max(
        8,
        Math.min(
          650,
          camera.current.distance * (event.deltaY > 0 ? 1.12 : 0.89),
        ),
      );
    };
    canvas.addEventListener('pointerdown', down);
    // Track an active gesture outside the hit-tested canvas. BYOND's embedded
    // browser can drop canvas pointer capture when the press begins on a drawn
    // body or when the pointer crosses an overlay; window tracking keeps the
    // gesture continuous in both cases.
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    canvas.addEventListener('lostpointercapture', cancel);
    canvas.addEventListener('contextmenu', contextMenu);
    canvas.addEventListener('wheel', wheel, { passive: false });
    render();
    return () => {
      cancelAnimationFrame(frame);
      canvas.removeEventListener('pointerdown', down);
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
      canvas.removeEventListener('lostpointercapture', cancel);
      canvas.removeEventListener('contextmenu', contextMenu);
      canvas.removeEventListener('wheel', wheel);
      gl.deleteProgram(planetProgram);
      gl.deleteProgram(simpleProgram);
      gl.deleteBuffer(sphereBuffer);
      gl.deleteBuffer(indexBuffer);
      gl.deleteBuffer(dynamicBuffer);
    };
  }, []);

  return (
    <div
      ref={container}
      style={{ height: '100%', position: 'relative', width: '100%' }}
    >
      <canvas
        ref={webgl}
        style={{
          cursor: 'grab',
          height: '100%',
          position: 'absolute',
          width: '100%',
        }}
      />
      <canvas
        ref={overlay}
        style={{
          height: '100%',
          pointerEvents: 'none',
          position: 'absolute',
          width: '100%',
        }}
      />
    </div>
  );
};
