const $ = (id) => document.getElementById(id);
const canvas = $('canvas');
const displayCtx = canvas.getContext('2d', { alpha: true });
const backCanvas = document.createElement('canvas');
let ctx = backCanvas.getContext('2d', { alpha: true });
const sceneCanvas = document.createElement('canvas');
const sceneCtx = sceneCanvas.getContext('2d', { alpha: false });
let gpu = null;
try { gpu = new MapGpuViewport($('gpu-canvas')); }
catch (error) { $('gpu-canvas').hidden = true; console.warn('GPU viewport unavailable:',error); }
const mapcore = new MapcoreClient();
mapcore.load();
const state = {
  map: '', size: [1, 1, 1], tiles: new Map(), sprites: {}, atlas: null, images: new Map(),
  bounds: null, selection: null, drag: null, pan: null, route: [], preview: null, cell: 24,
  viewId: 0, atlasLoading: false, selected: new Set(), selectMode: 'replace', routeDraw: false,
  camera: { x: 1, y: 1 }, frameIndex: new Map(), appearance: {}, selectionHistory: [], clipboard: null,
  mode: 'select', activeLayer: 'turf', selectedAtom: null, lastPoint: null, stroke: null,
  sceneDirty: true, previewQueue: Promise.resolve(),
  sceneAtoms: new Set(),
  warmPower: new Set(),
  hitMasks: new Map(), temporaryLayer: null,
  hitBoxes: new Map(),
  selectedNetwork: null, networkSelectionId: 0, strokeAnchorPort: null, strokeEndPort: null,
  strokeEndTarget: null, strokeEndStub: false,
  draft: null, draftId: 0,
};
const key = (x, y, z) => `${x},${y},${z}`;
function atomsAt(point) {
  if (state.preview?.map === state.map) {
    const changed = state.previewTiles?.get(key(point.x, point.y, point.z));
    if (changed) return changed.after;
  }
  return state.tiles.get(key(point.x,point.y,point.z))?.atoms || [];
}
let redrawPending = false;
function scheduleDraw() {
  if (redrawPending) return;
  redrawPending = true;
  requestAnimationFrame(() => { redrawPending = false; draw(); });
}

async function api(method, args = {}) {
  const response = await fetch('/api', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ method, args }),
  });
  const data = await response.json();
  if (!response.ok) throw Error(data.error || 'Request failed');
  return data;
}

function status(message) { $('status').textContent = message; }
function showError(message) {
  status(message);
  $('notice').textContent = message;
  $('notice').hidden = false;
  clearTimeout(state.noticeTimer);
  state.noticeTimer = setTimeout(() => { $('notice').hidden = true; }, 5000);
}
function showPanel(_side, panel) {
  const container = document.querySelector('.sidebar');
  for (const button of container.querySelectorAll('.pane-tabs button'))
    button.classList.toggle('active', button.dataset.panel === panel);
  for (const section of container.querySelectorAll('.pane-body > .panel'))
    section.hidden = section.dataset.panel !== panel;
  container.querySelector('.pane-body').scrollTop = 0;
}
function updateActionUI() {
  const action = $('action').value;
  const transform = ['move', 'copy'].includes(action);
  $('offsets').hidden = !transform;
  $('replace-row').hidden = !transform;
  $('layer').closest('label').hidden = transform;
  $('search').closest('label').hidden = transform || action === 'erase';
  $('atom').closest('label').hidden = transform || action === 'erase';
}
function selectedPoints() {
  const points = [...state.selected].map((item) => {
    const [x, y, z] = item.split(',').map(Number);
    return { x, y, z };
  });
  if (!points.length) throw Error('Select tiles on the map first.');
  return points;
}
function selectedRect() {
  const points = selectedPoints();
  const x1 = Math.min(...points.map((p) => p.x)), x2 = Math.max(...points.map((p) => p.x));
  const y1 = Math.min(...points.map((p) => p.y)), y2 = Math.max(...points.map((p) => p.y));
  const z = points[0].z;
  if (points.some((p) => p.z !== z) || points.length !== (x2 - x1 + 1) * (y2 - y1 + 1))
    throw Error('Move and copy need one solid rectangular selection.');
  return { x1, y1, x2, y2, z };
}
function selectionStatus() {
  $('selection').textContent = state.selected.size ? `${state.selected.size} tile${state.selected.size === 1 ? '' : 's'} selected` : 'Drag on the map to select tiles';
}
function applySelection(rect, mode) {
  if (state.lastCommit) { state.lastCommit = false; state.canUndoCommit = true; }
  state.selectionHistory.push(new Set(state.selected));
  if (mode === 'replace') state.selected.clear();
  for (let x = rect.x1; x <= rect.x2; x++) for (let y = rect.y1; y <= rect.y2; y++) {
    const id = key(x, y, rect.z);
    if (mode === 'subtract') state.selected.delete(id);
    else state.selected.add(id);
  }
  selectionStatus();
}
function areaColor(atom) {
  let hash = 0;
  for (let i = 0; i < atom.length; i++) hash = (Math.imul(hash, 31) + atom.charCodeAt(i)) | 0;
  return `hsla(${Math.abs(hash) % 360},65%,55%,.16)`;
}
function classify(atoms) {
  const turf = atoms.find((a) => a.startsWith('/turf/')) || '';
  if (turf.includes('/space')) return '#10181e';
  if (turf.includes('/wall')) return '#64777b';
  if (turf.includes('/floor')) return '#4d6265';
  return '#394e51';
}
function atomLayer(atom) {
  const path = atom.split('{')[0].trim();
  if (path.startsWith('/area/')) return 'area';
  if (path.startsWith('/turf/')) return 'turf';
  if (path.startsWith('/obj/structure/cable')) return 'power';
  if (path.startsWith('/obj/machinery/atmospherics/')) return 'atmos';
  if (path.startsWith('/obj/structure/disposalpipe')) return 'disposals';
  if (path.startsWith('/obj/machinery/power/apc')) return 'apc';
  return 'objects';
}
function imageFor(atom) {
  const frame = state.frameIndex.get(atom);
  const crop = frame?.crop;
  const url = frame?.url || state.sprites[atom];
  if (!url) return { loaded: false, failed: false };
  const load = (source) => {
    if (state.images.has(source)) return state.images.get(source);
    const img = new Image();
    const record = { img, loaded: false, failed: false };
    state.images.set(source, record);
    img.onload = () => { record.loaded = true; if (state.sceneAtoms.has(atom)) state.sceneDirty = true; scheduleDraw(); };
    img.onerror = () => { record.failed = true; if (state.sceneAtoms.has(atom)) state.sceneDirty = true; scheduleDraw(); };
    img.src = source;
    return record;
  };
  const record = load(url);
  if (frame && !record.loaded && state.sprites[atom] && state.sprites[atom] !== url) {
    const fallback = load(state.sprites[atom]);
    if (fallback.loaded) return { ...fallback, crop: null };
  }
  return { ...record, crop };
}
function visible(atom) {
  const layer = atomLayer(atom);
  if (layer === 'area') return $('show-areas').checked;
  if (layer === 'turf') return $('show-turf').checked;
  if (layer === 'objects') return $('show-objects').checked;
  if (layer === 'apc') return $('show-apc').checked;
  if (['power', 'atmos', 'disposals'].includes(layer)) return $(`show-${layer}`).checked;
  return true;
}
function renderOrder(atom) {
  if (atom.startsWith('/turf/')) return 0;
  if (atom.startsWith('/obj/effect/floor_decal')) return 1;
  if (atom.startsWith('/obj/structure/disposalpipe')) return 2;
  if (atom.startsWith('/obj/machinery/atmospherics/')) return 3;
  if (atom.startsWith('/obj/structure/cable')) return 4;
  if (atom.startsWith('/obj/effect/landmark')) return 9;
  return 5;
}
function drawAtom(atom, sx, sy, alphaScale = 1) {
  if (!visible(atom)) return;
  const layer = atomLayer(atom);
  const sprite = imageFor(atom);
  if (!sprite.loaded) return;
  const appearance = state.appearance[atom] || {};
  const crop = sprite.crop || [0, 0, sprite.img.naturalWidth, sprite.img.naturalHeight];
  const dx = sx + (appearance.pixel_x || 0) * state.cell / 32;
  const dy = sy - (appearance.pixel_y || 0) * state.cell / 32;
  ctx.save(); ctx.globalAlpha = (['power', 'atmos', 'disposals'].includes(layer) ?
    Math.max(.85, (appearance.alpha ?? 255) / 255) : (appearance.alpha ?? 255) / 255) * alphaScale;
  if (['power', 'atmos', 'disposals'].includes(layer)) ctx.filter = 'brightness(2.1)';
  ctx.drawImage(sprite.img, ...crop, dx, dy, crop[2] * state.cell / 32, crop[3] * state.cell / 32);
  ctx.restore();
}
function networkColor(layer, atom) {
  const palette = {red:'#ff5454',yellow:'#ffe350',green:'#6be96b',blue:'#5b9fff',
    pink:'#ff72ef',orange:'#ffad55',cyan:'#60eaff',white:'#e9f5f7'};
  if (layer === 'power') return palette[atom.split('{')[0].split('/').at(-1)] || palette.red;
  if (layer === 'atmos') return atom.includes('/supply') ? '#5b9fff' : '#ff5454';
  return '#ddd6b8';
}
function drawNetworkBlueprint(points, layer, atom, originX, originY) {
  if (!points.length || !['power','atmos','disposals'].includes(layer)) return;
  const centers = points.map((p) => [originX+(p.x-.5)*state.cell,originY-(p.y-.5)*state.cell]);
  ctx.save(); ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.globalAlpha = .38;
  ctx.strokeStyle = networkColor(layer,atom);
  ctx.lineWidth = Math.max(2,state.cell*.085);
  ctx.beginPath();
  centers.forEach(([x,y],i) => { if (i) ctx.lineTo(x,y); else ctx.moveTo(x,y); });
  if (centers.length === 1) { const [x,y] = centers[0]; ctx.lineTo(x+1,y); }
  ctx.stroke();
  ctx.restore();
}
function buildScene() {
  if (!state.bounds) return;
  const b = state.bounds, width = (b.x2 - b.x1 + 1) * 32, height = (b.y2 - b.y1 + 1) * 32;
  if (!gpu && (sceneCanvas.width !== width || sceneCanvas.height !== height)) {
    sceneCanvas.width = width; sceneCanvas.height = height;
  }
  const oldCtx = ctx, oldCell = state.cell;
  if (!gpu) {
    ctx = sceneCtx; state.cell = 32;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#10191b'; ctx.fillRect(0, 0, width, height);
  }
  const drawables = [], tiles = [];
  for (let y = b.y2; y >= b.y1; y--) for (let x = b.x1; x <= b.x2; x++) {
    const sx = (x - b.x1) * 32, sy = (b.y2 - y) * 32;
    const atoms = state.tiles.get(key(x, y, b.z))?.atoms || [];
    if (gpu) tiles.push({x,y,atoms});
    else { ctx.fillStyle = classify(atoms); ctx.fillRect(sx, sy, 32, 32); }
    atoms.forEach((atom, index) => {
      if (atomLayer(atom) !== 'area') drawables.push({ atom, sx, sy, index, order: renderOrder(atom) });
    });
    if (!gpu && $('show-areas').checked) {
      const area = atoms.find((atom) => atom.startsWith('/area/'));
      if (area) { ctx.fillStyle = areaColor(area); ctx.fillRect(sx, sy, 32, 32); }
    }
  }
  drawables.sort((a, b) => a.order - b.order ||
    (state.appearance[a.atom]?.layer || 0) - (state.appearance[b.atom]?.layer || 0) ||
    a.sy - b.sy || a.sx - b.sx || a.index - b.index);
  state.sceneAtoms = new Set(drawables.map(({atom}) => atom));
  if (gpu) gpu.setScene(b,tiles,drawables,{classify,areaColor,areas:$('show-areas').checked,
    visible,imageFor,appearance:state.appearance,atomLayer});
  else for (const { atom, sx, sy } of drawables) drawAtom(atom, sx, sy);
  if (!gpu && state.selectedNetwork) for (const member of state.selectedNetwork.members) {
    if (member.z !== b.z || member.x < b.x1 || member.x > b.x2 || member.y < b.y1 || member.y > b.y2) continue;
    highlightNetworkAtom(member.atom,(member.x-b.x1)*32,(b.y2-member.y)*32);
  }
  ctx = oldCtx; state.cell = oldCell; state.sceneDirty = false;
}
function visibleDraftDiff() {
  const previous = state.preview?.map === state.map ? state.preview.diff || [] : [];
  const current = state.draft?.diff || [];
  if (!current.length) return previous;
  const combined = new Map(previous.map((tile) => [key(tile.x,tile.y,tile.z),tile]));
  for (const tile of current) {
    const id=key(tile.x,tile.y,tile.z), original=combined.get(id);
    combined.set(id,original ? {...tile,before:original.before} : tile);
  }
  return [...combined.values()];
}
function drawDraftTiles(originX,originY,z,changes) {
  if (!changes?.length) return;
  ctx.save(); ctx.imageSmoothingEnabled = false;
  for (const tile of changes) {
    if (tile.z !== z) continue;
    const sx = Math.round(originX+(tile.x-1)*state.cell);
    const sy = Math.round(originY-tile.y*state.cell);
    if (sx+state.cell<0 || sy+state.cell<0 || sx>canvas.clientWidth || sy>canvas.clientHeight) continue;
    ctx.fillStyle = classify(tile.after); ctx.fillRect(sx,sy,state.cell,state.cell);
    if ($('show-areas').checked) {
      const area = tile.after.find((atom) => atom.startsWith('/area/'));
      if (area) { ctx.fillStyle = areaColor(area); ctx.fillRect(sx,sy,state.cell,state.cell); }
    }
    const atoms = tile.after.map((atom,index) => ({atom,index})).filter(({atom}) => atomLayer(atom) !== 'area');
    atoms.sort((a,b) => renderOrder(a.atom)-renderOrder(b.atom) ||
      (state.appearance[a.atom]?.layer || 0)-(state.appearance[b.atom]?.layer || 0) || a.index-b.index);
    for (const {atom} of atoms) drawAtom(atom,sx,sy,
      !tile.before.includes(atom) && ['power','atmos','disposals'].includes(atomLayer(atom)) ? .72 : 1);
    const selected = state.selectedNetwork?.byTile.get(key(tile.x,tile.y,z));
    if (selected) {
      const updated = tile.after.find((atom) => selected.some((old) => atomLayer(old) === atomLayer(atom)));
      if (updated) highlightNetworkAtom(updated,sx,sy);
    }
  }
  ctx.restore();
}
function drawGpuDraft(changes) {
  const bounds=state.bounds, tiles=[], drawables=[];
  if (bounds) for (const tile of changes) {
    if (tile.z !== bounds.z || tile.x < bounds.x1 || tile.x > bounds.x2 ||
        tile.y < bounds.y1 || tile.y > bounds.y2) continue;
    tiles.push({x:tile.x,y:tile.y,atoms:tile.after});
    const sx=(tile.x-bounds.x1)*32, sy=(bounds.y2-tile.y)*32;
    tile.after.forEach((atom,index) => {
      if (atomLayer(atom) !== 'area') drawables.push({atom,sx,sy,index,order:renderOrder(atom)});
    });
  }
  drawables.sort((a,b) => a.order-b.order ||
    (state.appearance[a.atom]?.layer || 0)-(state.appearance[b.atom]?.layer || 0) ||
    a.sy-b.sy || a.sx-b.sx || a.index-b.index);
  gpu.setDraftScene(bounds,tiles,drawables,{classify,areaColor,areas:$('show-areas').checked,
    visible,imageFor,appearance:state.appearance,atomLayer});
}
function draw() {
  const ratio = devicePixelRatio || 1, w = canvas.clientWidth, h = canvas.clientHeight;
  if (!w || !h) return;
  const pixelWidth = Math.ceil(w * ratio), pixelHeight = Math.ceil(h * ratio);
  if (backCanvas.width !== pixelWidth || backCanvas.height !== pixelHeight) {
    backCanvas.width = pixelWidth; backCanvas.height = pixelHeight;
  }
  if (canvas.width !== pixelWidth || canvas.height !== pixelHeight) {
    canvas.width = pixelWidth; canvas.height = pixelHeight;
  }
  ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
  if (gpu) ctx.clearRect(0, 0, w, h);
  else { ctx.fillStyle = '#10191b'; ctx.fillRect(0, 0, w, h); }
  if (!state.bounds) return;
  if (state.sceneDirty) buildScene();
  const visibleChanges=visibleDraftDiff();
  if (gpu) {
    drawGpuDraft(visibleChanges);
    gpu.draw(state.camera,state.cell,w,h,ratio);
  }
  const z = +$('z').value;
  const originX = w / 2 - (state.camera.x - .5) * state.cell;
  const originY = h / 2 + (state.camera.y - .5) * state.cell;
  const x1 = Math.max(1, Math.floor((0 - originX) / state.cell) + 1);
  const x2 = Math.min(state.size[0], Math.ceil((w - originX) / state.cell));
  const y1 = Math.max(1, Math.floor((originY - h) / state.cell) + 1);
  const y2 = Math.min(state.size[1], Math.ceil(originY / state.cell));
  const b = state.bounds;
  const proposed = new Map((state.preview?.map === state.map ? state.preview.diff : [])
    .filter((d) => d.z === z).map((d) => [key(d.x, d.y, d.z), d]));
  ctx.save(); ctx.imageSmoothingEnabled = false;
  const sourceX = Math.max(0, Math.floor((x1 - b.x1) * 32));
  const sourceY = Math.max(0, Math.floor((b.y2 - y2) * 32));
  const sourceW = Math.min(sceneCanvas.width - sourceX, Math.max(0, (x2 - x1 + 1) * 32));
  const sourceH = Math.min(sceneCanvas.height - sourceY, Math.max(0, (y2 - y1 + 1) * 32));
  if (!gpu && sourceW > 0 && sourceH > 0) ctx.drawImage(sceneCanvas, sourceX, sourceY, sourceW, sourceH,
    Math.round(originX + (b.x1 - 1 + sourceX / 32) * state.cell),
    Math.round(originY - (b.y2 - sourceY / 32) * state.cell),
    sourceW * state.cell / 32, sourceH * state.cell / 32);
  ctx.restore();
  if (gpu && state.selectedNetwork) for (const member of state.selectedNetwork.members) {
    if (member.z !== z || member.x < x1 || member.x > x2 || member.y < y1 || member.y > y2) continue;
    highlightNetworkAtom(member.atom,
      Math.round(originX+(member.x-1)*state.cell),Math.round(originY-member.y*state.cell));
  }
  if (!gpu) drawDraftTiles(originX,originY,z,visibleChanges);
  if (proposed.size || state.selected.size || state.selectedAtom || state.selectedNetwork)
  for (let y = y2; y >= y1; y--) for (let x = x1; x <= x2; x++) {
    const sx = Math.round(originX + (x - 1) * state.cell), sy = Math.round(originY - y * state.cell);
    const changed = proposed.get(key(x, y, z));
    if (changed) {
      const removed = changed.before.filter((a) => !changed.after.includes(a) && atomLayer(a) !== 'area');
      const genuinelyRemoved = removed.filter((atom) => !changed.after.some((next) => atomLayer(next) === atomLayer(atom)));
      if (genuinelyRemoved.length) {
        const sprite = imageFor(genuinelyRemoved.at(-1));
        if (sprite.loaded) {
          const crop = sprite.crop || [0, 0, sprite.img.naturalWidth, sprite.img.naturalHeight];
          ctx.save(); ctx.globalAlpha = .4;
          ctx.drawImage(sprite.img, ...crop, sx, sy, state.cell, state.cell);
          ctx.restore();
        }
        ctx.strokeStyle = '#ff6c6c'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.moveTo(sx + 3, sy + 3); ctx.lineTo(sx + state.cell - 3, sy + state.cell - 3); ctx.stroke();
        ctx.lineWidth = 1;
      }
      ctx.fillStyle = '#ffd479';
      ctx.beginPath(); ctx.moveTo(sx, sy); ctx.lineTo(sx + Math.min(7, state.cell / 3), sy);
      ctx.lineTo(sx, sy + Math.min(7, state.cell / 3)); ctx.closePath(); ctx.fill();
    }
    const atomSelectedHere = state.selectedAtom?.point.x === x && state.selectedAtom?.point.y === y && state.selectedAtom?.point.z === z;
    if (state.selected.has(key(x, y, z)) && !atomSelectedHere &&
        !state.selectedNetwork?.byTile.has(key(x,y,z))) {
      ctx.fillStyle = '#2fbac84a'; ctx.fillRect(sx, sy, state.cell, state.cell);
      ctx.strokeStyle = '#52e0ea'; ctx.strokeRect(sx + .5, sy + .5, state.cell, state.cell);
    }
    if (atomSelectedHere) outlineAtom(state.selectedAtom.atom,sx,sy,true);
  }
  if (state.selection) {
    const r = state.selection, sx = originX + (r.x1 - 1) * state.cell, sy = originY - r.y2 * state.cell;
    const width = (r.x2 - r.x1 + 1) * state.cell, height = (r.y2 - r.y1 + 1) * state.cell;
    ctx.fillStyle = '#2fbac835'; ctx.fillRect(sx, sy, width, height);
    ctx.strokeStyle = '#52e0ea'; ctx.lineWidth = 2; ctx.strokeRect(sx + 1, sy + 1, width - 2, height - 2); ctx.lineWidth = 1;
  }
  if (!state.draft) drawNetworkBlueprint(state.route,$('layer').value,$('atom').value.trim(),originX,originY);
  const activeStroke = state.stroke ? {points:state.stroke, mode:state.strokeMode,
    layer:state.activeLayer, atom:brushAtom().split('{')[0]} : state.pendingStroke;
  if (activeStroke) {
    const stroke = activeStroke.points;
    const atom = brushAtom().split('{')[0];
    const network = activeStroke.mode === 'place' && ['power','atmos','disposals'].includes(activeStroke.layer);
    // Network drafts draw their actual sprite states over the cached scene.
    for (const p of network ? [] : stroke) {
      const sx = Math.round(originX + (p.x - 1) * state.cell), sy = Math.round(originY - p.y * state.cell);
      const previewAtom = atom;
      if (activeStroke.mode === 'place' && previewAtom) state.sprites[previewAtom] ||= `/sprite?atom=${encodeURIComponent(previewAtom)}`;
      const sprite = activeStroke.mode === 'place' && previewAtom ? imageFor(previewAtom) : null;
      if (sprite?.loaded) {
        const crop = sprite.crop || [0, 0, sprite.img.naturalWidth, sprite.img.naturalHeight];
        ctx.save(); ctx.globalAlpha = .65; ctx.drawImage(sprite.img, ...crop, sx, sy, state.cell, state.cell); ctx.restore();
      } else if (activeStroke.mode === 'delete') {
        ctx.strokeStyle = '#ff6c6c'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.moveTo(sx + 2, sy + 2); ctx.lineTo(sx + state.cell - 2, sy + state.cell - 2); ctx.stroke(); ctx.lineWidth = 1;
      }
    }
  }
  displayCtx.setTransform(1, 0, 0, 1, 0, 0);
  if (gpu) displayCtx.clearRect(0,0,canvas.width,canvas.height);
  displayCtx.drawImage(backCanvas, 0, 0);
}
function coordinate(event) {
  if (!state.bounds) return null;
  const bounds = canvas.getBoundingClientRect();
  const originX = canvas.clientWidth / 2 - (state.camera.x - .5) * state.cell;
  const originY = canvas.clientHeight / 2 + (state.camera.y - .5) * state.cell;
  const x = Math.floor((event.clientX - bounds.left - originX) / state.cell) + 1;
  const y = Math.ceil((originY - (event.clientY - bounds.top)) / state.cell);
  return x >= 1 && x <= state.size[0] && y >= 1 && y <= state.size[1]
    ? { x, y, z: +$('z').value } : null;
}
function hitMask(atom, sprite, crop) {
  const id = `${atom}|${sprite.img.src}|${crop.join(',')}`;
  if (state.hitMasks.has(id)) return state.hitMasks.get(id);
  const surface = document.createElement('canvas'); surface.width = crop[2]; surface.height = crop[3];
  const surfaceCtx = surface.getContext('2d', {willReadFrequently:true});
  surfaceCtx.drawImage(sprite.img, ...crop, 0, 0, crop[2], crop[3]);
  const data = surfaceCtx.getImageData(0, 0, crop[2], crop[3]).data;
  const alpha = new Uint8Array(crop[2] * crop[3]);
  for (let i = 0; i < alpha.length; i++) alpha[i] = data[i * 4 + 3];
  if (state.hitMasks.size > 4096) state.hitMasks.clear();
  state.hitMasks.set(id, alpha);
  return alpha;
}
function spriteBounds(atom, sprite, crop) {
  const id = `${atom}|${sprite.img.src}|${crop.join(',')}`;
  if (state.hitBoxes.has(id)) return state.hitBoxes.get(id);
  const mask = hitMask(atom,sprite,crop);
  let x1 = crop[2], y1 = crop[3], x2 = -1, y2 = -1;
  for (let y = 0; y < crop[3]; y++) for (let x = 0; x < crop[2]; x++) {
    if (!mask[y*crop[2]+x]) continue;
    x1 = Math.min(x1,x); y1 = Math.min(y1,y); x2 = Math.max(x2,x); y2 = Math.max(y2,y);
  }
  const bounds = x2 < 0 ? null : {x1,y1,x2,y2};
  if (state.hitBoxes.size > 4096) state.hitBoxes.clear();
  state.hitBoxes.set(id,bounds);
  return bounds;
}
function outlineAtom(atom, sx, sy, strong = false) {
  const sprite = imageFor(atom);
  const crop = sprite.loaded ? sprite.crop || [0,0,sprite.img.naturalWidth,sprite.img.naturalHeight] : null;
  const box = crop ? spriteBounds(atom,sprite,crop) : null;
  const appearance = state.appearance[atom] || {};
  const bx = box ? sx + ((appearance.pixel_x || 0) + box.x1) * state.cell / 32 : sx;
  const by = box ? sy + (box.y1 - (appearance.pixel_y || 0)) * state.cell / 32 : sy;
  const bw = box ? (box.x2-box.x1+1) * state.cell / 32 : state.cell;
  const bh = box ? (box.y2-box.y1+1) * state.cell / 32 : state.cell;
  ctx.strokeStyle = strong ? '#75c9d7' : '#397884'; ctx.lineWidth = strong ? 1.5 : 1;
  ctx.strokeRect(bx - 1.5, by - 1.5, bw + 3, bh + 3); ctx.lineWidth = 1;
}
function highlightNetworkAtom(atom, sx, sy) {
  const sprite = imageFor(atom);
  if (!sprite.loaded) return;
  const crop = sprite.crop || [0,0,sprite.img.naturalWidth,sprite.img.naturalHeight];
  const appearance = state.appearance[atom] || {};
  ctx.save();
  ctx.globalAlpha = .78;
  ctx.filter = 'grayscale(1) brightness(2)';
  ctx.drawImage(sprite.img,...crop,sx+(appearance.pixel_x || 0)*state.cell/32,
    sy-(appearance.pixel_y || 0)*state.cell/32,crop[2]*state.cell/32,crop[3]*state.cell/32);
  ctx.restore();
}
function hitAtomAt(event) {
  const tile = coordinate(event);
  if (!tile) return null;
  const bounds = canvas.getBoundingClientRect();
  const px = event.clientX - bounds.left, py = event.clientY - bounds.top;
  const originX = canvas.clientWidth / 2 - (state.camera.x - .5) * state.cell;
  const originY = canvas.clientHeight / 2 + (state.camera.y - .5) * state.cell;
  const candidates = [];
  for (let y = Math.max(1, tile.y - 4); y <= Math.min(state.size[1], tile.y + 4); y++)
    for (let x = Math.max(1, tile.x - 4); x <= Math.min(state.size[0], tile.x + 4); x++) {
      const point = {x,y,z:tile.z};
      const atoms = atomsAt(point);
      atoms.forEach((atom,index) => {
        if (visible(atom) && atomLayer(atom) !== 'area') candidates.push({atom,point,index,
          order:renderOrder(atom), sx:(x-1)*state.cell, sy:-y*state.cell});
      });
    }
  candidates.sort((a,b) => a.order-b.order ||
    (state.appearance[a.atom]?.layer || 0)-(state.appearance[b.atom]?.layer || 0) ||
    a.sy-b.sy || a.sx-b.sx || a.index-b.index);
  const ordered = candidates.reverse();
  let turfHit = null;
  const exact = [];
  const grace = [];
  for (const item of ordered) {
    const {atom,point} = item;
    const appearance = state.appearance[atom] || {};
    const sx = originX+(point.x-1)*state.cell+(appearance.pixel_x || 0)*state.cell/32;
    const sy = originY-point.y*state.cell-(appearance.pixel_y || 0)*state.cell/32;
    if (atomLayer(atom) === 'turf') {
      if (px >= sx && px < sx+state.cell && py >= sy && py < sy+state.cell) turfHit ||= {point,atom};
      continue;
    }
    const sprite = imageFor(atom);
    if (!sprite.loaded) {
      if (px >= sx && px < sx+state.cell && py >= sy && py < sy+state.cell) exact.push({point,atom});
      continue;
    }
    const crop = sprite.crop || [0,0,sprite.img.naturalWidth,sprite.img.naturalHeight];
    const ix = Math.floor((px-sx)*32/state.cell), iy = Math.floor((py-sy)*32/state.cell);
    const mask = hitMask(atom,sprite,crop);
    if (ix >= 0 && iy >= 0 && ix < crop[2] && iy < crop[3] && mask[iy*crop[2]+ix] > 0) {
      exact.push({point,atom}); continue;
    }
    const radius = Math.max(1, Math.ceil(4*32/state.cell));
    let distance = Infinity;
    for (let y = Math.max(0,iy-radius); y <= Math.min(crop[3]-1,iy+radius); y++)
      for (let x = Math.max(0,ix-radius); x <= Math.min(crop[2]-1,ix+radius); x++)
        if (mask[y*crop[2]+x] > 0) distance = Math.min(distance, Math.hypot(x-ix,y-iy));
    if (distance <= radius) grace.push({point,atom,distance});
  }
  grace.sort((a,b) => a.distance-b.distance);
  const preferred = state.activeLayer !== 'turf' ? state.activeLayer : null;
  const hit = (preferred && (exact.find((item) => atomLayer(item.atom) === preferred) ||
    grace.find((item) => atomLayer(item.atom) === preferred))) || exact[0] || grace[0];
  if (hit) return {point:hit.point,atom:hit.atom};
  if (turfHit) return turfHit;
  const area = atomsAt(tile).find((a) => a.startsWith('/area/'));
  return area && visible(area) ? {point:tile,atom:area} : null;
}
function closeContext() { $('tile-context').hidden = true; }
function openContext(point, clientX, clientY) {
  const menu = $('tile-context');
  const tile = state.tiles.get(key(point.x, point.y, point.z));
  const atoms = tile?.atoms || [];
  menu.replaceChildren();
  const heading = document.createElement('strong'); heading.textContent = `Tile ${point.x}, ${point.y}, ${point.z}`; menu.append(heading);
  const addButton = (label, handler, className = '') => {
    const button = document.createElement('button'); button.textContent = label; button.className = className;
    button.onclick = () => { closeContext(); handler(); }; menu.append(button);
  };
  for (const atom of atoms) {
    const row = document.createElement('div'); row.className = 'context-atom';
    const title = document.createElement('span'); title.textContent = atom.split('{')[0].split('/').slice(-2).join('/'); title.title = atom;
    row.append(title);
    const actions = document.createElement('div'); actions.className = 'context-actions';
    const action = (label, fn) => { const b = document.createElement('button'); b.textContent = label; b.title = `${label}: ${atom}`; b.onclick = () => { closeContext(); fn(); }; actions.append(b); };
    action('Pick', () => { $('layer').value = atomLayer(atom); $('atom').value = atom.split('{')[0]; $('action').value = 'paint'; updateActionUI(); catalog(); showPanel('tools', 'edit'); document.body.classList.add('tools-open'); });
    action('Copy', () => { state.clipboard = atom; status(`Copied ${atom.split('{')[0]}`); });
    action('Edit', () => editAtom(point, atom));
    if (['power', 'atmos', 'disposals'].includes(atomLayer(atom)))
      action('Select', () => { selectLayer(atomLayer(atom)); selectAtom(point, atom); openPalette(); });
    if (['power', 'atmos', 'disposals'].includes(atomLayer(atom)))
      action('Split', () => previewOperation({action:'network_split', at:point, layer:atomLayer(atom), atom}));
    if (!['area', 'turf'].includes(atomLayer(atom))) action('Remove', () => previewOperation({ action: 'remove_atom', at: point, atom }));
    row.append(actions); menu.append(row);
  }
  if (state.clipboard) addButton(`Paste ${state.clipboard.split('{')[0].split('/').at(-1)}`, () => previewOperation({ action: 'paste_atom', at: point, atom: state.clipboard }));
  if (['power', 'atmos', 'disposals'].includes(state.activeLayer)) {
    addButton('Join ends', () => previewOperation({action:'network_join', at:point, layer:state.activeLayer, atom:$('atom').value.trim()}));
    if (state.activeLayer !== 'disposals') addButton('Cross', () => previewOperation({action:'network_cross', at:point, layer:state.activeLayer, atom:$('atom').value.trim()}));
  }
  addButton('Select from tile', () => showTileSelect(point));
  menu.hidden = false;
  menu.style.left = `${Math.min(clientX, innerWidth - menu.offsetWidth - 12)}px`;
  menu.style.top = `${Math.min(clientY, innerHeight - menu.offsetHeight - 12)}px`;
}
function editAtom(point, atom) {
  const form = $('atom-editor');
  $('edit-title').textContent = `Edit ${atom.split('{')[0].split('/').at(-1)} at ${point.x}, ${point.y}`;
  $('edit-path').value = atom.split('{')[0];
  for (const name of ['dir', 'icon_state', 'color', 'pixel_x', 'pixel_y', 'layer']) {
    const match = atom.match(new RegExp(`\\b${name}\\s*=\\s*("[^"]*"|[-\\w.]+)`));
    $(`edit-${name}`).value = match ? match[1].replace(/^"|"$/g, '') : '';
  }
  form.hidden = false;
  $('edit-apply').onclick = () => {
    const vars = {};
    for (const name of ['dir', 'icon_state', 'color', 'pixel_x', 'pixel_y', 'layer'])
      if ($(`edit-${name}`).value.trim()) vars[name] = $(`edit-${name}`).value.trim();
    form.hidden = true;
    previewOperation({ action: 'edit_atom', at: point, atom, path: $('edit-path').value.trim(), vars });
  };
}
async function previewOperation(operation, pendingStroke = null) {
  state.previewQueue = state.previewQueue.catch(() => {}).then(async () => {
    try {
      if (state.preview?.map === state.map && !state.preview.operations)
        throw Error('Save or discard the existing preview before adding another stroke.');
      const previous = state.preview?.map === state.map ? state.preview.operations : [];
      const operations = [...previous, operation];
      const oldId = state.preview?.preview_id;
      const result = await api('preview', { map: state.map, operations });
      showPreview(result);
      if (oldId && oldId !== result.preview_id) api('dismiss', { preview_id: oldId }).catch(() => {});
      status('Change ready to review and save.');
    } catch (error) { showError(error.message); }
    finally {
      if (pendingStroke && state.pendingStroke === pendingStroke) {
        state.pendingStroke = null;
        scheduleDraw();
      }
    }
  });
  return state.previewQueue;
}
function extendRoute(point) {
  const last = state.route.at(-1);
  if (!last) { state.route.push(point); scheduleDraw(); return; }
  let x = last.x, y = last.y;
  while (x !== point.x || y !== point.y) {
    if (x !== point.x) x += Math.sign(point.x - x);
    if (y !== point.y && ($('layer').value === 'power' || x === point.x)) y += Math.sign(point.y - y);
    if (!state.route.some((p) => p.x === x && p.y === y && p.z === point.z))
      state.route.push({ x, y, z: point.z });
  }
  scheduleDraw();
}
function selectAtom(point, atom) {
  state.selectedNetwork = null;
  state.selectedAtom = { point, atom };
  state.lastPoint = point;
  const layer = atomLayer(atom);
  selectLayer(layer);
  const selectionId = ++state.networkSelectionId;
  $('atom').value = atom.split('{')[0];
  $('brush-type').value = atom.split('{')[0];
  warmPowerSprites();
  const appearance = state.appearance[atom] || {};
  for (const [id, value] of [['brush-dir', appearance.dir], ['brush-state', appearance.icon_state],
    ['brush-color', appearance.color], ['brush-pixel-x', appearance.pixel_x], ['brush-pixel-y', appearance.pixel_y]])
    $(id).value = value ?? '';
  $('network-actions').hidden = !['power', 'atmos', 'disposals'].includes(atomLayer(atom));
  $('tool-tip').textContent = atom;
  scheduleDraw();
  if (['power','atmos','disposals'].includes(layer)) {
    const operations = state.preview?.map === state.map ? state.preview.operations || [] : [];
    api('network_component',{map:state.map,at:point,atom,operations}).then((result) => {
      if (selectionId !== state.networkSelectionId) return;
      const byTile = new Map();
      for (const member of result.members) {
        const id = key(member.x,member.y,member.z);
        if (!byTile.has(id)) byTile.set(id,[]);
        byTile.get(id).push(member.atom);
      }
      state.selectedNetwork = {layer,members:result.members,byTile};
      for (const member of result.members) state.selected.add(key(member.x,member.y,member.z));
      selectionStatus();
      state.sceneDirty = true;
      $('tool-tip').textContent = `${result.members.length} connected ${layer} segment${result.members.length === 1 ? '' : 's'}`;
      scheduleDraw();
    }).catch(() => {});
  }
}
function showTileSelect(point) {
  const atoms = atomsAt(point);
  const menu = $('tile-select');
  $('tile-select-title').textContent = `Tile ${point.x}, ${point.y}, ${point.z}`;
  const selected = state.selectedAtom?.point.x === point.x && state.selectedAtom?.point.y === point.y &&
    state.selectedAtom?.point.z === point.z ? state.selectedAtom.atom : null;
  const detail = $('tile-select-detail');
  detail.replaceChildren();
  if (selected) {
    const preview = document.createElement('img'); preview.src = `/sprite?atom=${encodeURIComponent(selected)}`;
    preview.alt = ''; preview.onerror = () => { preview.hidden = true; };
    const summary = document.createElement('div');
    const path = document.createElement('strong'); path.textContent = selected.split('{')[0];
    const layer = document.createElement('small'); layer.textContent = `${atomLayer(selected)}${selected.includes('{') ? ' · ' + selected.split('{')[1].replace(/}\s*$/, '') : ''}`;
    summary.append(path,layer); detail.append(preview,summary);
  }
  const ordered = [...atoms].sort((a,b) => renderOrder(b)-renderOrder(a));
  $('tile-select-list').replaceChildren(...ordered.map((atom) => {
    const button = document.createElement('button');
    button.className = 'tile-select-item';
    button.textContent = atom.split('{')[0].split('/').slice(-2).join('/') || atom;
    button.title = atom;
    button.classList.toggle('active', selected === atom);
    button.onclick = () => { selectAtom(point, atom); showTileSelect(point); };
    return button;
  }));
  menu.hidden = false;
}
function selectLayer(layer) {
  const previous = state.activeLayer;
  if (previous !== layer) { state.selectedNetwork = null; state.networkSelectionId++; }
  if (state.temporaryLayer && state.temporaryLayer !== layer) {
    const prior = $(`show-${state.temporaryLayer === 'area' ? 'areas' : state.temporaryLayer}`);
    prior.checked = false; prior.dispatchEvent(new Event('change'));
    state.temporaryLayer = null;
  }
  state.activeLayer = layer; $('layer').value = layer;
  const chosen = $(`show-${layer === 'area' ? 'areas' : layer}`);
  if (!chosen.checked) {
    chosen.checked = true; chosen.dispatchEvent(new Event('change'));
    state.temporaryLayer = layer;
  }
  syncLayerRail();
  $('network-actions').hidden = !['power', 'atmos', 'disposals'].includes(layer) || !state.lastPoint;
  if (layer === 'power') $('atom').value = '/obj/structure/cable' + ($('wire-color').value ? '/' + $('wire-color').value : '');
  if (layer === 'atmos') $('atom').value = `/obj/machinery/atmospherics/pipe/simple/hidden/${$('atmos-type').value}`;
  if (layer === 'disposals') $('atom').value = '/obj/structure/disposalpipe/segment';
  if (layer === 'apc') $('atom').value = '/obj/machinery/power/apc';
  if (previous !== layer && ['turf', 'area', 'objects'].includes(layer)) $('atom').value = '';
  $('brush-type').value = $('atom').value;
  warmPowerSprites();
  $('tool-config').hidden = !['power', 'atmos'].includes(layer);
  $('wire-config').hidden = layer !== 'power';
  $('atmos-config').hidden = layer !== 'atmos';
  state.sceneDirty = true;
  catalog();
  scheduleDraw();
}
function syncLayerRail() {
  for (const button of document.querySelectorAll('[data-layer-button]')) {
    const layer = button.dataset.layerButton;
    const checkbox = $(`show-${layer === 'area' ? 'areas' : layer}`);
    const eye = document.querySelector(`[data-layer-eye="${layer}"]`);
    button.classList.toggle('active', layer === state.activeLayer);
    button.setAttribute('aria-pressed', String(layer === state.activeLayer));
    eye.classList.toggle('off', !checkbox.checked);
    eye.setAttribute('aria-label', `${checkbox.checked ? 'Hide' : 'Show'} ${button.textContent}`);
    eye.setAttribute('aria-pressed', String(checkbox.checked));
  }
}
function openPalette() { $('tool-palette').hidden = false; }
function setMode(mode) {
  state.mode = mode;
  for (const button of document.querySelectorAll('[data-mode]')) button.classList.toggle('active', button.dataset.mode === mode);
  $('brush-label').hidden = false;
  $('tool-config').hidden = !['power', 'atmos'].includes(state.activeLayer);
  $('tool-tip').textContent = {select:'Click an atom or drag an area', eyedrop:'Click to pick a mapped type',
    fill:'Click to fill matching tiles', place:'Click or drag to place', network:'Click or drag a route',
    delete:'Click or drag to remove'}[mode];
  scheduleDraw();
}
function appendStroke(point) {
  if (!state.stroke) return false;
  const originalLength = state.stroke.length;
  const originalEnd = state.stroke.at(-1);
  if (originalEnd && point.x === originalEnd.x && point.y === originalEnd.y &&
      point.z === originalEnd.z) return false;
  let last = state.stroke.at(-1);
  const network = state.strokeMode === 'place' && ['power','atmos','disposals'].includes(state.activeLayer);
  if (network && state.activeLayer === 'power' && last) {
    const dx = point.x-last.x, dy = point.y-last.y;
    const steps = Math.max(Math.abs(dx),Math.abs(dy));
    for (let i=1;i<=steps && state.stroke.length<2500;i++) {
      const next = {x:last.x+Math.round(dx*i/steps),y:last.y+Math.round(dy*i/steps),z:point.z};
      const previous = state.stroke.at(-2), current = state.stroke.at(-1);
      if (current?.x === next.x && current?.y === next.y) continue;
      if (previous?.x === next.x && previous?.y === next.y) state.stroke.pop();
      else state.stroke.push(next);
    }
    return state.stroke.length !== originalLength || state.stroke.at(-1) !== originalEnd;
  }
  let steps = 0;
  while (last && (last.x !== point.x || last.y !== point.y) && state.stroke.length < 2500 && steps++ < 2500) {
    let dx = Math.sign(point.x-last.x), dy = Math.sign(point.y-last.y);
    if (network && state.activeLayer !== 'power' && dx && dy) {
      if (Math.abs(point.x-last.x) >= Math.abs(point.y-last.y)) dy = 0; else dx = 0;
    }
    const next = {x:last.x+dx,y:last.y+dy,z:point.z};
    const previous = state.stroke.at(-2);
    const prior = state.stroke.findIndex((p) => p.x === next.x && p.y === next.y && p.z === next.z);
    if (network && previous?.x === next.x && previous?.y === next.y) state.stroke.pop();
    else if (prior >= 0 && !network) break;
    else state.stroke.push(next);
    last = state.stroke.at(-1);
  }
  return state.stroke.length !== originalLength || state.stroke.at(-1) !== originalEnd;
}
function scheduleNetworkDraft() {
  if (!state.stroke || state.strokeMode !== 'place' || state.stroke.length < 2 ||
      !['power','atmos','disposals'].includes(state.activeLayer)) return;
  state.draftOperation = {action:'route',layer:state.activeLayer,atom:brushAtom().split('{')[0],
    points:[...state.stroke, ...(state.strokeEndTarget ? [state.strokeEndTarget] : [])].map((point) => ({...point})),
    snap_start:false, snap_end:false, auto_join_neighbors:false,
    ...(state.activeLayer === 'power' && state.strokeEndStub ? {end_stub:true} : {}),
    ...(state.activeLayer === 'power' && state.strokeAnchorPort ? {anchor_port:state.strokeAnchorPort} : {}),
    ...(state.activeLayer === 'power' && state.strokeEndPort ? {end_port:state.strokeEndPort} : {})};
  if (mapcore.exports) {
    try {
      const diff = mapcore.route(state.draftOperation,atomsAt,(point) =>
        state.tiles.has(key(point.x,point.y,point.z)) ||
        state.previewTiles?.has(key(point.x,point.y,point.z)));
      if (diff) {
        clearTimeout(state.draftTimer); state.draftTimer = null;
        state.draft = {diff};
        for (const tile of diff) for (const atom of tile.after)
          state.sprites[atom] ||= `/sprite?atom=${encodeURIComponent(atom)}`;
        scheduleDraw();
        return;
      }
    } catch { state.draft = null; scheduleDraw(); return; }
  }
  if (state.draftTimer || state.draftLoading) return;
  const draftId = state.draftId;
  state.draftTimer = setTimeout(async () => {
    state.draftTimer = null;
    state.draftLoading = true;
    const operation = state.draftOperation;
    try {
      const previous = state.preview?.map === state.map ? state.preview.operations || [] : [];
      const result = await api('draft',{map:state.map,operations:[...previous,operation]});
      if (draftId !== state.draftId || operation !== state.draftOperation) return;
      state.draft = result;
      Object.assign(state.sprites,result.sprites || {});
      scheduleDraw();
    } catch { /* Final preview reports route errors. */ }
    finally {
      state.draftLoading = false;
      if (draftId === state.draftId && state.stroke && operation !== state.draftOperation)
        scheduleNetworkDraft();
    }
  },0);
}
function clearNetworkDraft(preserve = false) {
  ++state.draftId;
  clearTimeout(state.draftTimer);
  state.draftTimer = null;
  state.draftOperation = null;
  if (state.draft && !preserve) { state.draft = null; scheduleDraw(); }
}
function brushAtom() { return $('brush-type').value.trim() || $('atom').value.trim(); }
async function warmPowerSprites() {
  if (state.activeLayer !== 'power') return;
  const base = brushAtom().split('{')[0];
  if (!base.startsWith('/obj/structure/cable') || state.warmPower.has(base)) return;
  state.warmPower.add(base);
  const dirs = [1,2,4,8,5,6,9,10];
  const atoms = dirs.map((dir) => `${base}{icon_state = "0-${dir}"}`);
  for (let i=0;i<dirs.length;i++) for (let j=i+1;j<dirs.length;j++)
    atoms.push(`${base}{icon_state = "${Math.min(dirs[i],dirs[j])}-${Math.max(dirs[i],dirs[j])}"}`);
  try {
    const atlas = await api('atlas',{atoms});
    for (const [atom,crop] of Object.entries(atlas.frames || {}))
      state.frameIndex.set(atom,{url:atlas.url,crop});
    Object.assign(state.appearance,atlas.appearance || {});
    if (Object.keys(atlas.frames || {}).length) imageFor(Object.keys(atlas.frames)[0]);
  } catch { state.warmPower.delete(base); }
}
function nearestNetworkMember(candidates, mouseX, mouseY, originX, originY) {
  let best = null;
  for (const member of candidates) {
    const centerX = originX + (member.x - .5) * state.cell;
    const centerY = originY - (member.y - .5) * state.cell;
    if (Math.hypot(centerX-mouseX,centerY-mouseY) > state.cell*2) continue;
    let distance = Math.hypot(centerX-mouseX,centerY-mouseY);
    const sprite = member.atom && imageFor(member.atom);
    if (sprite?.loaded) {
      const crop = sprite.crop || [0,0,sprite.img.naturalWidth,sprite.img.naturalHeight];
      const mask = hitMask(member.atom,sprite,crop);
      const appearance = state.appearance[member.atom] || {};
      const sx = originX+(member.x-1)*state.cell+(appearance.pixel_x || 0)*state.cell/32;
      const sy = originY-member.y*state.cell-(appearance.pixel_y || 0)*state.cell/32;
      let pixels = Infinity;
      for (let y=0;y<crop[3];y++) for (let x=0;x<crop[2];x++) {
        if (!mask[y*crop[2]+x]) continue;
        pixels = Math.min(pixels,Math.hypot(sx+(x+.5)*state.cell/32-mouseX,
          sy+(y+.5)*state.cell/32-mouseY));
      }
      if (pixels < Infinity) distance = pixels;
    }
    if (!best || distance < best.distance - .01 ||
        Math.abs(distance-best.distance) < .01 && member.atom === state.selectedAtom?.atom)
      best = {point:member,distance};
  }
  return best;
}
function nearestPowerPort(member, mouseX, mouseY, originX, originY) {
  if (!member?.atom) return null;
  const iconState = state.appearance[member.atom]?.icon_state ||
    member.atom.match(/icon_state\s*=\s*"([^"]+)"/)?.[1] || '0-1';
  const ports = iconState.match(/^(\d+)-(\d+)$/)?.slice(1).map(Number).filter(Boolean) || [];
  const deltas = {1:[0,-1],2:[0,1],4:[1,0],8:[-1,0],5:[1,-1],6:[1,1],9:[-1,-1],10:[-1,1]};
  const cx = originX+(member.x-.5)*state.cell, cy = originY-(member.y-.5)*state.cell;
  const nearest = ports.reduce((best,port) => {
    const delta = deltas[port]; if (!delta) return best;
    const distance = Math.hypot(cx+delta[0]*state.cell/2-mouseX,cy+delta[1]*state.cell/2-mouseY);
    return !best || distance < best.distance ? {port,distance} : best;
  },null);
  return nearest && nearest.distance <= state.cell*.3 ? nearest.port : null;
}
function powerPortAtPointer(event, point) {
  if (!point || state.activeLayer !== 'power') return null;
  const candidates = atomsAt(point).filter((atom) => atomLayer(atom) === 'power')
    .map((atom) => ({...point,atom}));
  if (!candidates.length) return null;
  const bounds = canvas.getBoundingClientRect();
  const mouseX = event.clientX - bounds.left, mouseY = event.clientY - bounds.top;
  const originX = canvas.clientWidth / 2 - (state.camera.x - .5) * state.cell;
  const originY = canvas.clientHeight / 2 + (state.camera.y - .5) * state.cell;
  const nearest = nearestNetworkMember(candidates,mouseX,mouseY,originX,originY);
  return nearestPowerPort(nearest?.point,mouseX,mouseY,originX,originY);
}
function powerEndStub(event, point) {
  return state.activeLayer === 'power' && state.selectedNetwork?.layer === 'power' && point &&
    state.selectedNetwork.byTile.has(key(point.x,point.y,point.z)) && !powerPortAtPointer(event,point);
}
function updateStrokeCornerIntent(sample, previous, last) {
  if (!sample || !previous || !last || !state.strokeSegmentStartPointer ||
      Math.abs(last.x-previous.x)+Math.abs(last.y-previous.y) !== 1 ||
      state.strokeCardinalCommitted) return;
  const start = state.strokeSegmentStartPointer;
  const horizontal = last.x !== previous.x;
  const along = Math.abs((horizontal ? sample.x-start.x : sample.y-start.y));
  const across = Math.abs((horizontal ? sample.y-start.y : sample.x-start.x));
  if (along > .22 && across < Math.max(.09,along*.24)) {
    state.strokeCardinalCommitted = true;
    state.strokeCornerEntry = false;
  } else if (across > .08 && across > along*.22) state.strokeCornerEntry = true;
}
function strokePointAtPointer(event, point) {
  if (!point || state.activeLayer !== 'power' || !state.stroke?.length || !state.strokePointerOrigin)
    return point;
  const origin = state.strokePointerOrigin;
  const offsetX = (event.clientX-origin.x)/state.cell;
  const offsetY = (origin.y-event.clientY)/state.cell;
  const target = point;
  const previous = state.stroke.at(-2), last = state.stroke.at(-1);
  const retreat = state.strokeDiagonalRetreat;
  if (retreat && previous?.x === retreat.diagonal.x && previous?.y === retreat.diagonal.y &&
      last?.x === retreat.middle.x && last?.y === retreat.middle.y &&
      target.x === retreat.anchor.x && target.y === retreat.anchor.y) {
    state.stroke.pop();
    state.stroke.pop();
    state.strokeDiagonalRetreat = null;
    return target;
  }
  if (retreat && (target.x !== retreat.middle.x || target.y !== retreat.middle.y))
    state.strokeDiagonalRetreat = null;
  updateStrokeCornerIntent({x:offsetX,y:offsetY},previous,last);
  if (previous && last && Math.abs(target.x-previous.x) === 1 &&
      Math.abs(target.y-previous.y) === 1 &&
      Math.abs(last.x-previous.x)+Math.abs(last.y-previous.y) === 1 &&
      state.strokeCornerEntry)
    state.stroke.pop();
  else if (previous && last && Math.abs(last.x-previous.x) === 1 &&
      Math.abs(last.y-previous.y) === 1 &&
      Math.abs(target.x-previous.x)+Math.abs(target.y-previous.y) === 1) {
    // A diagonal retrace often passes through a side tile one axis at a time.
    // Remember that side tile so reaching the prior tile removes both steps.
    // Leaving the side tile elsewhere keeps it as a deliberate turn.
    state.strokeDiagonalRetreat = {anchor:previous,diagonal:last,middle:target};
  }
  return target;
}
function networkEndTarget(event, point) {
  if (!point || state.selectedNetwork?.layer !== state.activeLayer) return null;
  const candidates = (state.selectedNetwork.byTile.get(key(point.x,point.y,point.z)) || [])
    .map((atom) => ({...point,atom}));
  if (!candidates.length) return null;
  const bounds = canvas.getBoundingClientRect();
  const mouseX = event.clientX-bounds.left, mouseY = event.clientY-bounds.top;
  const originX = canvas.clientWidth/2-(state.camera.x-.5)*state.cell;
  const originY = canvas.clientHeight/2+(state.camera.y-.5)*state.cell;
  const nearest = nearestNetworkMember(candidates,mouseX,mouseY,originX,originY);
  if (!nearest || nearest.distance > state.cell*.3) return null;
  const port = state.activeLayer === 'power' ? nearestPowerPort(nearest.point,mouseX,mouseY,originX,originY) : null;
  if (state.activeLayer === 'power' && !port) return null;
  return {point:{x:nearest.point.x,y:nearest.point.y,z:nearest.point.z},port};
}
function brushVars() {
  const fields = {dir:$('brush-dir').value, icon_state:$('brush-state').value,
    color:$('brush-color').value, pixel_x:$('brush-pixel-x').value, pixel_y:$('brush-pixel-y').value};
  return Object.fromEntries(Object.entries(fields).filter(([, value]) => String(value).trim() !== ''));
}
function operationForStroke(points, mode) {
  if (mode === 'delete') {
    if (points.length === 1 && state.selectedAtom?.point.x === points[0].x &&
        state.selectedAtom?.point.y === points[0].y && state.selectedAtom?.point.z === points[0].z &&
        ['power', 'atmos', 'disposals'].includes(atomLayer(state.selectedAtom.atom)))
      return {action:'remove_atom', at:points[0], atom:state.selectedAtom.atom};
    return {action:'erase', layer:state.activeLayer, points};
  }
  if (['power', 'atmos', 'disposals'].includes(state.activeLayer)) {
    const atom = brushAtom().split('{')[0];
    if (points.length >= 2) return {action:'route', layer:state.activeLayer, atom, points,
      snap_start:false, snap_end:false, auto_join_neighbors:false,
      ...(state.activeLayer === 'power' && state.strokeEndStub ? {end_stub:true} : {}),
      ...(state.activeLayer === 'power' && state.strokeAnchorPort ? {anchor_port:state.strokeAnchorPort} : {}),
      ...(state.activeLayer === 'power' && state.strokeEndPort ? {end_port:state.strokeEndPort} : {})};
    const p = points[0];
    if (atomsAt(p).some((a) => atomLayer(a) === state.activeLayer)) return null;
    if (state.selectedNetwork?.layer !== state.activeLayer) return {action:'place_atom',
      layer:state.activeLayer,atom,vars:brushVars(),points};
    const offsets = state.activeLayer === 'power' ?
      [[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]] : [[1,0],[-1,0],[0,1],[0,-1]];
    const neighbors = offsets.map(([dx,dy]) => ({x:p.x+dx,y:p.y+dy,z:p.z})).filter((n) =>
      atomsAt(n).some((a) => atomLayer(a) === state.activeLayer &&
        (state.activeLayer === 'power' || a.split('{')[0].split('/').at(-1) === atom.split('/').at(-1))));
    if (neighbors.length >= 2) return {action:'route', layer:state.activeLayer, atom, points:[neighbors[0],p,neighbors[1]]};
    if (neighbors.length === 1) return {action:'route', layer:state.activeLayer, atom, points:[neighbors[0],p]};
  }
  return {action:'place_atom', layer:state.activeLayer, atom:brushAtom().split('{')[0], vars:brushVars(), points};
}
async function fillAt(point) {
  const layer = state.activeLayer;
  const source = state.tiles.get(key(point.x, point.y, point.z));
  if (!source) { showError('Load this part of the map first.'); return; }
  const signature = (tile) => (tile?.atoms || []).filter((a) => atomLayer(a) === layer).join('|');
  const match = signature(source), visited = new Set(), queue = [point], points = [];
  while (queue.length && points.length < 2500) {
    const p = queue.shift(), id = key(p.x, p.y, p.z);
    if (visited.has(id)) continue;
    visited.add(id);
    if (signature(state.tiles.get(id)) !== match || !state.tiles.has(id)) continue;
    points.push(p);
    for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
      const nx = p.x + dx, ny = p.y + dy;
      if (nx >= 1 && ny >= 1 && nx <= state.size[0] && ny <= state.size[1]) queue.push({x:nx,y:ny,z:p.z});
    }
  }
  if (!points.length) return;
  previewOperation(operationForStroke(points, 'place'));
}
function showPreview(result) {
  state.preview = result;
  clearNetworkDraft();
  state.previewTiles = new Map(result.diff.map((tile) => [key(tile.x,tile.y,tile.z),tile]));
  state.dismissedPreview = null;
  Object.assign(state.sprites, result.sprites || {});
  $('change-review').hidden = false;
  $('save').disabled = result.map !== state.map;
  $('discard').disabled = false;
  $('proposal-count').textContent = `${result.changed_tiles} tile${result.changed_tiles === 1 ? '' : 's'}`;
  const describe = (atom) => atom.split('{')[0].split('/').slice(-2).join('/') + (atom.includes('{') ? ' (edited)' : '');
  $('proposal').textContent = [
    `${result.changed_tiles} tile${result.changed_tiles === 1 ? '' : 's'} will change. Nothing has been saved yet.`,
    ...result.warnings.map((w) => `⚠ ${w}`),
    ...result.diff.slice(0, 40).map((d) => {
      const removed = d.before.filter((atom) => !d.after.includes(atom)).map((atom) => `− ${describe(atom)}`);
      const added = d.after.filter((atom) => !d.before.includes(atom)).map((atom) => `+ ${describe(atom)}`);
      return `(${d.x}, ${d.y}, ${d.z})  ${[...removed, ...added].join('  ')}`;
    }),
    ...(result.diff.length > 40 ? [`… ${result.diff.length - 40} more tiles`] : []),
  ].join('\n\n');
  draw();
}
function viewRect() {
  const z = +$('z').value;
  const halfX = Math.ceil(canvas.clientWidth / state.cell / 2) + 12;
  const halfY = Math.ceil(canvas.clientHeight / state.cell / 2) + 12;
  const cx = Math.round(state.camera.x), cy = Math.round(state.camera.y);
  return { x1: Math.max(1, cx - halfX), y1: Math.max(1, cy - halfY),
    x2: Math.min(state.size[0], cx + halfX), y2: Math.min(state.size[1], cy + halfY), z };
}
function viewNeedsFetch() {
  const b = state.bounds, r = viewRect();
  return !b || b.z !== r.z || r.x1 < b.x1 || r.y1 < b.y1 || r.x2 > b.x2 || r.y2 > b.y2;
}
function uncoveredViewRects(next, previous) {
  if (!previous || previous.z !== next.z || next.x2 < previous.x1 || next.x1 > previous.x2 ||
      next.y2 < previous.y1 || next.y1 > previous.y2) return [next];
  const result = [];
  const left = Math.max(next.x1, previous.x1), right = Math.min(next.x2, previous.x2);
  const bottom = Math.max(next.y1, previous.y1), top = Math.min(next.y2, previous.y2);
  if (next.x1 < left) result.push({...next, x2:left-1});
  if (right < next.x2) result.push({...next, x1:right+1});
  if (next.y1 < bottom) result.push({...next, x1:left, x2:right, y2:bottom-1});
  if (top < next.y2) result.push({...next, x1:left, x2:right, y1:top+1});
  return result;
}
function boundedViewRects(regions, maxTiles = 12000) {
  return regions.flatMap((region) => {
    const rows = Math.max(1, Math.floor(maxTiles / (region.x2 - region.x1 + 1)));
    const result = [];
    for (let y = region.y1; y <= region.y2; y += rows)
      result.push({...region, y1:y, y2:Math.min(region.y2, y + rows - 1)});
    return result;
  });
}
async function loadView(force = false) {
  try {
    const viewId = ++state.viewId;
    const z = +$('z').value;
    if (z < 1 || z > state.size[2]) throw Error('Deck out of range.');
    if (!force && !viewNeedsFetch()) return;
    const rect = viewRect();
    const regions = boundedViewRects(force ? [rect] : uncoveredViewRects(rect, state.bounds));
    const responses = await Promise.all(regions.map((region) => api('inspect', {map:state.map,rect:region})));
    if (viewId !== state.viewId) return;
    state.bounds = rect;
    for (const data of responses) for (const tile of data.tiles)
      state.tiles.set(key(tile.x, tile.y, tile.z), tile);
    state.atlasLoading = true;
    state.sceneDirty = true;
    status(`${state.map} · deck ${z} · ${responses.reduce((sum, data) => sum + data.tiles.length, 0)} new tiles`);
    draw();
    const missing = [...new Set(responses.flatMap((data) => data.sprite_atoms))]
      .filter((atom) => !state.frameIndex.has(atom));
    if (!missing.length) { state.atlasLoading = false; return; }
    for (let start = 0; start < missing.length; start += 96) {
      const batch = missing.slice(start, start + 96);
      api('atlas', {atoms:batch}).then((atlas) => {
        for (const [atom, crop] of Object.entries(atlas.frames || {}))
          if (!state.frameIndex.has(atom)) state.frameIndex.set(atom, {url:atlas.url,crop});
        Object.assign(state.appearance, atlas.appearance || {});
        state.sceneDirty = true;
        scheduleDraw();
      }).catch((error) => status(`Map loaded; sprites unavailable: ${error.message}`));
    }
    state.atlasLoading = false;
  } catch (error) { status(error.message); }
}
function clampCamera() {
  state.camera.x = Math.max(.5, Math.min(state.size[0] + .5, state.camera.x));
  state.camera.y = Math.max(.5, Math.min(state.size[1] + .5, state.camera.y));
  $('cx').value = Math.round(state.camera.x);
  $('cy').value = Math.round(state.camera.y);
  scheduleDraw();
  if (viewNeedsFetch()) {
    clearTimeout(state.fetchTimer);
    state.fetchTimer = setTimeout(loadView, state.pan ? 120 : 90);
  }
}
async function chooseMap() {
  try {
    state.map = $('map').value;
    state.selected.clear(); state.selectedAtom = null; state.selectedNetwork = null;
    state.networkSelectionId++; state.route = []; state.selection = null; selectionStatus();
    const info = await api('info', { map: state.map });
    state.size = info.size;
    state.tiles.clear(); state.frameIndex.clear(); state.appearance = {}; state.bounds = null;
    state.sceneDirty = true;
    $('dimensions').textContent = `${info.size[0]} × ${info.size[1]} tiles · ${info.size[2]} deck(s)`;
    $('z').max = info.size[2]; $('z').value = 1;
    $('cx').value = Math.ceil(info.size[0] / 2); $('cy').value = Math.ceil(info.size[1] / 2);
    state.camera = { x: +$('cx').value, y: +$('cy').value };
    await loadView();
    catalog();
  } catch (error) { status(error.message); }
}
async function catalog() {
  if (!state.map) return;
  try {
    const data = await api('catalog', { map: state.map, layer: $('layer').value, query: $('search').value });
    $('catalog').replaceChildren(...data.paths.map((path) => {
      const option = document.createElement('option'); option.value = path; return option;
    }));
  } catch (error) { status(error.message); }
}
canvas.addEventListener('pointerdown', (event) => {
  closeContext();
  if (event.button === 1 || event.button === 2 || (event.button === 0 && state.spaceHeld)) {
    state.pan = { x: event.clientX, y: event.clientY, cx: state.camera.x, cy: state.camera.y,
      button: event.button, moved: false, point: coordinate(event) };
    canvas.setPointerCapture(event.pointerId); return;
  }
  const point = coordinate(event); if (!point) return;
  state.lastPoint = point;
  if (event.ctrlKey || state.mode === 'delete') {
    state.stroke = [point]; state.strokeMode = 'delete'; canvas.setPointerCapture(event.pointerId); return;
  }
  if (state.pickHeld || state.mode === 'eyedrop') {
    const hit = hitAtomAt(event);
    if (hit) { selectAtom(hit.point, hit.atom); setMode('place'); showTileSelect(hit.point); }
    return;
  }
  if (state.mode === 'fill') { fillAt(point); return; }
  if (state.mode === 'place') {
    const members = state.selectedNetwork?.layer === state.activeLayer ? state.selectedNetwork.members : [];
    const candidates = members.filter((member) => member.z === point.z &&
      Math.max(Math.abs(member.x-point.x),Math.abs(member.y-point.y)) <= 1);
    const bounds = canvas.getBoundingClientRect();
    const mouseX = event.clientX - bounds.left, mouseY = event.clientY - bounds.top;
    const originX = canvas.clientWidth / 2 - (state.camera.x - .5) * state.cell;
    const originY = canvas.clientHeight / 2 + (state.camera.y - .5) * state.cell;
    const hit = hitAtomAt(event);
    const hitMember = hit && candidates.find((member) => member.x === hit.point.x &&
      member.y === hit.point.y && member.z === hit.point.z && (!member.atom || member.atom === hit.atom));
    const nearest = hitMember ? {point:hitMember,distance:0} :
      nearestNetworkMember(candidates,mouseX,mouseY,originX,originY);
    const adjacent = nearest && Math.max(Math.abs(nearest.point.x-point.x),Math.abs(nearest.point.y-point.y)) <= 1;
    const anchor = adjacent && (nearest.point.x !== point.x || nearest.point.y !== point.y) && nearest.point.z === point.z ?
      {x:nearest.point.x,y:nearest.point.y,z:nearest.point.z} : point;
    state.stroke = [anchor]; state.strokeMode = 'place';
    state.strokePointerOrigin = {x:event.clientX,y:event.clientY,point};
    state.strokePointerSample = {x:0,y:0};
    state.strokeNodePointer = {x:0,y:0};
    state.strokeSegmentStartPointer = null;
    state.strokeCornerEntry = false;
    state.strokeCardinalCommitted = false;
    state.strokeDiagonalRetreat = null;
    state.strokeAnchorPort = adjacent && state.activeLayer === 'power' ?
      nearestPowerPort(nearest.point,mouseX,mouseY,originX,originY) : null;
    state.strokeEndPort = null;
    state.strokeEndTarget = null;
    state.strokeEndStub = false;
    if (anchor !== point) { appendStroke(point); scheduleNetworkDraft(); }
    canvas.setPointerCapture(event.pointerId); scheduleDraw(); return;
  }
  if ($('action').value === 'route') {
    $('action').value = 'paint';
  }
  state.drag = point;
  state.dragMode = event.altKey || (event.ctrlKey && event.shiftKey) ? 'subtract' : event.ctrlKey || event.shiftKey ? 'add' : state.selectMode;
  state.selection = null;
  canvas.setPointerCapture(event.pointerId);
});
canvas.addEventListener('pointermove', (event) => {
  const cursor = $('cursor-tool');
  cursor.hidden = false;
  cursor.style.left = `${event.clientX + 16}px`;
  cursor.style.top = `${event.clientY + 16}px`;
  cursor.textContent = event.ctrlKey || state.mode === 'delete' ? 'Delete' : state.pickHeld ? 'Pick' :
    `${state.mode === 'place' && ['power','atmos','disposals'].includes(state.activeLayer) ? 'Connect' : state.mode} · ${state.activeLayer}`;
  if (state.pan) {
    const dx = event.clientX - state.pan.x, dy = event.clientY - state.pan.y;
    if (Math.abs(dx) + Math.abs(dy) > 4) state.pan.moved = true;
    state.camera.x = state.pan.cx - dx / state.cell;
    state.camera.y = state.pan.cy + dy / state.cell;
    clampCamera();
    return;
  }
  const point = coordinate(event);
  if (point) {
    const area = state.tiles.get(key(point.x, point.y, point.z))?.atoms.find((atom) => atom.startsWith('/area/'));
    $('map-coord').textContent = `${point.x}, ${point.y}, ${point.z}${area ? ' · ' + area.split('/').slice(-2).join('/') : ''}`;
  }
  if (state.stroke) {
    const oldLength = state.stroke.length, oldEnd = state.stroke.at(-1);
    const oldNodePointer = state.strokeNodePointer;
    const next = point && strokePointAtPointer(event,point);
    if (point && state.strokePointerOrigin) state.strokePointerSample = {
      x:(event.clientX-state.strokePointerOrigin.x)/state.cell,
      y:(state.strokePointerOrigin.y-event.clientY)/state.cell};
    const moved = next && (appendStroke(next) || state.stroke.length !== oldLength ||
      state.stroke.at(-1) !== oldEnd);
    if (moved) {
      const last = state.stroke.at(-1), previous = state.stroke.at(-2);
      const sample = state.strokePointerSample;
      if (sample && oldNodePointer) {
        state.strokeSegmentStartPointer = oldNodePointer;
        state.strokeCornerEntry = false;
        state.strokeCardinalCommitted = false;
        updateStrokeCornerIntent(sample,previous,last);
        state.strokeNodePointer = sample;
      }
    }
    const strokeEnd = state.stroke.at(-1);
    const endTarget = state.strokeMode === 'place' ? networkEndTarget(event,point) : null;
    const snapped = endTarget && (endTarget.point.x !== strokeEnd.x || endTarget.point.y !== strokeEnd.y) &&
      !state.stroke.some((p) => p.x === endTarget.point.x && p.y === endTarget.point.y && p.z === endTarget.point.z);
    const target = snapped ? endTarget.point : null;
    const changedTarget = key(target?.x,target?.y,target?.z) !==
      key(state.strokeEndTarget?.x,state.strokeEndTarget?.y,state.strokeEndTarget?.z);
    state.strokeEndTarget = target;
    const endPort = endTarget?.port || (state.selectedNetwork?.layer === state.activeLayer &&
      point && strokeEnd.x === point.x && strokeEnd.y === point.y ?
      powerPortAtPointer(event,point) : null);
    const changedPort = state.strokeEndPort !== endPort;
    state.strokeEndPort = endPort;
    const endStub = !endTarget && powerEndStub(event,point);
    const changedStub = state.strokeEndStub !== endStub;
    state.strokeEndStub = endStub;
    if (moved || changedPort || changedTarget || changedStub) scheduleNetworkDraft();
    if (moved || changedPort || changedTarget || changedStub) scheduleDraw();
    return;
  }
  if (point && state.routeDraw) { extendRoute(point); return; }
  if (!point || !state.drag) return;
  if (point.x === state.drag.x && point.y === state.drag.y && !state.selection) return;
  state.selection = { x1: Math.min(state.drag.x, point.x), y1: Math.min(state.drag.y, point.y),
    x2: Math.max(state.drag.x, point.x), y2: Math.max(state.drag.y, point.y), z: point.z };
  $('selection').textContent = `${state.dragMode === 'subtract' ? 'Remove' : state.dragMode === 'add' ? 'Add' : 'Select'} ${state.selection.x1}, ${state.selection.y1} → ${state.selection.x2}, ${state.selection.y2}`;
  scheduleDraw();
});
canvas.addEventListener('pointerup', (event) => {
  if (state.pan) {
    const pan = state.pan; state.pan = null;
    if (pan.button === 2 && !pan.moved && pan.point && !event.shiftKey) openContext(pan.point, event.clientX, event.clientY);
    else if (viewNeedsFetch()) loadView();
    return;
  }
  if (state.stroke) {
    const releasePoint = coordinate(event);
    if (releasePoint) appendStroke(strokePointAtPointer(event,releasePoint));
    const endTarget = state.strokeMode === 'place' ? networkEndTarget(event,releasePoint) : null;
    if (endTarget && !state.stroke.some((p) => p.x === endTarget.point.x &&
        p.y === endTarget.point.y && p.z === endTarget.point.z)) appendStroke(endTarget.point);
    state.strokeEndPort = endTarget?.port || (state.selectedNetwork?.layer === state.activeLayer ?
      powerPortAtPointer(event,releasePoint) : null);
    state.strokeEndStub = !endTarget && powerEndStub(event,releasePoint);
    const points = state.stroke, mode = state.strokeMode; state.stroke = null;
    clearNetworkDraft(true);
    const op = operationForStroke(points, mode);
    state.strokeAnchorPort = null;
    state.strokeEndPort = null;
    state.strokeEndTarget = null;
    state.strokeEndStub = false;
    state.strokePointerOrigin = null;
    state.strokePointerSample = null;
    state.strokeNodePointer = null;
    state.strokeSegmentStartPointer = null;
    state.strokeCornerEntry = false;
    state.strokeCardinalCommitted = false;
    state.strokeDiagonalRetreat = null;
    if (op) {
      const pending = {points,mode,layer:state.activeLayer,atom:brushAtom().split('{')[0]};
      state.pendingStroke = pending;
      previewOperation(op,pending);
    }
    scheduleDraw(); return;
  }
  if (state.routeDraw) {
    state.routeDraw = false;
    if (state.mode === 'network' && state.route.length >= 2) {
      const points = [...state.route]; state.route = [];
      previewOperation({action:'route', layer:state.activeLayer, atom:$('atom').value.trim(), points});
      scheduleDraw();
    }
    return;
  }
  const point = coordinate(event), start = state.drag; state.drag = null;
  const hit = point && start && start.x === point.x && start.y === point.y ? hitAtomAt(event) : null;
  if (state.selection || start && point && start.x === point.x && start.y === point.y) {
    if (hit) state.selection = {x1:hit.point.x,y1:hit.point.y,x2:hit.point.x,y2:hit.point.y,z:hit.point.z};
    else if (!state.selection) state.selection = {x1:point.x,y1:point.y,x2:point.x,y2:point.y,z:point.z};
    applySelection(state.selection, state.dragMode);
    state.selection = null;
  }
  if (point) {
    const tile = state.tiles.get(key(point.x, point.y, point.z));
    if (hit) selectAtom(hit.point, hit.atom);
    else if (start && start.x === point.x && start.y === point.y) {
      state.selectedAtom = null; state.selectedNetwork = null; state.networkSelectionId++;
      state.sceneDirty = true;
    }
    if (start && start.x === point.x && start.y === point.y) showTileSelect(hit?.point || point);
  }
  draw();
});
canvas.addEventListener('pointerleave', () => { $('cursor-tool').hidden = true; });
canvas.addEventListener('contextmenu', (event) => { if (!event.shiftKey) event.preventDefault(); });
canvas.addEventListener('wheel', (event) => {
  event.preventDefault();
  const next = Math.max(12, Math.min(64, Math.round(state.cell * (event.deltaY < 0 ? 1.12 : 1 / 1.12))));
  const px = event.clientX - canvas.getBoundingClientRect().left - canvas.clientWidth / 2;
  const py = event.clientY - canvas.getBoundingClientRect().top - canvas.clientHeight / 2;
  state.camera.x += px / state.cell - px / next;
  state.camera.y -= py / state.cell - py / next;
  state.cell = next;
  $('zoom').value = next;
  clampCamera();
  clearTimeout(state.zoomTimer); state.zoomTimer = setTimeout(() => { if (viewNeedsFetch()) loadView(); }, 130);
}, { passive: false });
$('preview').onclick = async () => {
  try {
    const action = $('action').value, layer = $('layer').value, atom = $('atom').value.trim();
    let operation;
    if (action === 'move' || action === 'copy') operation = { action, source: selectedRect(), dx: +$('dx').value, dy: +$('dy').value, replace: $('replace').checked };
    else if (action === 'route') operation = { action, layer, atom, points: state.route };
    else operation = { action, layer, points: selectedPoints(), ...(action === 'erase' ? {} : { atom }) };
    await previewOperation(operation);
    status('Preview ready. Review the highlighted tiles and changes before saving.');
  } catch (error) { showError(error.message); }
};
$('save').onclick = async () => {
  try {
    if (!state.preview) return;
    const result = await api('commit', { preview_id: state.preview.preview_id });
    state.preview = null; state.previewTiles = null; state.lastCommit = true; state.canUndoCommit = true; state.selectionHistory = []; $('save').disabled = true;
    state.sceneDirty = true;
    $('discard').disabled = true;
    $('proposal-count').textContent = 'Saved';
    $('proposal').textContent = `Saved ${result.changed_tiles} tiles.\nBackup: ${result.backup}`;
    $('change-review').hidden = true;
    status(`Saved ${result.saved}`); await loadView(true);
  } catch (error) { showError(error.message); }
};
$('undo').onclick = async () => {
  try {
    const result = await api('undo');
    state.preview = null; state.previewTiles = null; state.lastCommit = false; state.canUndoCommit = false; $('save').disabled = true;
    state.sceneDirty = true;
    $('discard').disabled = true;
    $('proposal-count').textContent = 'Undone';
    $('proposal').textContent = 'Last Map Studio save undone.';
    $('change-review').hidden = true;
    status(`Restored ${result.restored}`); await loadView(true);
  } catch (error) { showError(error.message); }
};
$('clear').onclick = () => {
  state.dismissedPreview = state.preview?.preview_id;
  if (state.dismissedPreview) api('dismiss', { preview_id: state.dismissedPreview }).catch(() => {});
  state.selection = null; state.selected.clear(); state.selectedAtom = null;
  state.selectedNetwork = null; state.networkSelectionId++;
  state.route = []; state.preview = null; state.previewTiles = null;
  state.sceneDirty = true;
  $('save').disabled = true; $('selection').textContent = 'Drag on the map to select an area';
  $('discard').disabled = true;
  $('proposal-count').textContent = 'No preview'; $('proposal').textContent = 'Preview cleared.'; draw();
  $('change-review').hidden = true;
};
$('discard').onclick = async () => {
  if (!state.preview) return;
  const previewId = state.preview.preview_id;
  state.dismissedPreview = previewId;
  state.preview = null; state.previewTiles = null;
  state.sceneDirty = true;
  $('save').disabled = true;
  $('discard').disabled = true;
  $('proposal-count').textContent = 'No preview';
  $('proposal').textContent = 'Proposal discarded. The map was not changed.';
  $('change-review').hidden = true;
  status('Proposal discarded.');
  draw();
  try { await api('dismiss', { preview_id: previewId }); }
  catch (error) { showError(error.message); }
};
$('clear-selection').onclick = () => { state.selectionHistory.push(new Set(state.selected)); state.selected.clear();
  state.selectedAtom = null; state.selectedNetwork = null; state.networkSelectionId++;
  state.selection = null; state.sceneDirty = true; selectionStatus(); draw(); };
$('load').onclick = () => { state.camera = { x: +$('cx').value, y: +$('cy').value }; clampCamera(); loadView(); };
for (const button of document.querySelectorAll('.pane-tabs button'))
  button.onclick = () => showPanel(button.dataset.side, button.dataset.panel);
function activateDock(button) {
  for (const other of document.querySelectorAll('.tool-dock > button'))
    if (other.id !== 'quick-areas' && other.id !== 'quick-tools')
      other.classList.toggle('active', other === button);
}
function selectMode(mode, button) {
  $('action').value = 'paint';
  updateActionUI();
  state.selectMode = mode;
  state.route = [];
  $('active-tool').textContent = mode === 'add' ? 'Add selection' : mode === 'subtract' ? 'Remove selection' : 'Select';
  status(mode === 'add' ? 'Drag to add tiles. Shift also adds.' : mode === 'subtract' ? 'Drag to remove tiles. Alt also removes.' : 'Click to inspect; drag to replace selection.');
  activateDock(button);
  $('tool-config').hidden = true;
  document.body.classList.remove('tools-open');
  draw();
}
$('quick-select').onclick = () => selectMode('replace', $('quick-select'));
for (const button of document.querySelectorAll('.tool-dock [data-preset-index]'))
  button.onclick = () => {
    document.querySelectorAll('.preset')[+button.dataset.presetIndex].click();
    state.selectMode = 'replace'; state.selected.clear(); selectionStatus();
    $('active-tool').textContent = button.textContent;
    activateDock(button);
    $('tool-config').hidden = $('action').value !== 'route';
    if (button.id === 'quick-cable') {
      $('config-title').textContent = 'Cable settings';
      $('wire-config').hidden = false; $('atmos-config').hidden = true;
      $('atom').value = '/obj/structure/cable' + ($('wire-color').value ? '/' + $('wire-color').value : '');
    } else {
      $('config-title').textContent = 'Disposal route';
      $('wire-config').hidden = true; $('atmos-config').hidden = true;
    }
    if (button.dataset.presetIndex < 4) {
      const layer = $('layer').value;
      $(`show-${layer}`).checked = true;
    }
    document.body.classList.remove('tools-open');
    status(`${button.textContent}: ${$('action').value === 'route' ? 'drag a route or click adjacent tiles, then stage the edit.' : 'click one tile, then stage the edit.'}`);
    draw();
  };
$('quick-atmos').onclick = () => {
  document.querySelectorAll('.preset')[$('atmos-type').value === 'scrubbers' ? 2 : 1].click();
  state.selectMode = 'replace'; state.selected.clear(); selectionStatus();
  $('show-atmos').checked = true;
  $('config-title').textContent = 'Atmos settings';
  $('wire-config').hidden = true; $('atmos-config').hidden = false;
  $('tool-config').hidden = false;
  $('active-tool').textContent = 'Atmos'; activateDock($('quick-atmos'));
  document.body.classList.remove('tools-open');
  status('Atmos: choose supply or scrubbers, then draw a route and stage the edit.');
  draw();
};
$('wire-color').onchange = () => {
  if ($('layer').value !== 'power') return;
  $('atom').value = '/obj/structure/cable' + ($('wire-color').value ? '/' + $('wire-color').value : '');
  $('brush-type').value = $('atom').value;
  $('active-tool').textContent = `Cable · ${$('wire-color').selectedOptions[0].textContent}`;
  warmPowerSprites();
  scheduleDraw();
};
$('atmos-type').onchange = () => {
  if ($('layer').value !== 'atmos') return;
  $('atom').value = `/obj/machinery/atmospherics/pipe/simple/hidden/${$('atmos-type').value}`;
  $('brush-type').value = $('atom').value;
  $('active-tool').textContent = `Atmos · ${$('atmos-type').selectedOptions[0].textContent}`;
  scheduleDraw();
};
$('close-config').onclick = () => { $('tool-config').hidden = true; };
$('stage-route').onclick = () => $('preview').click();
$('clear-route').onclick = () => { state.route = []; scheduleDraw(); status('Route cleared.'); };
$('quick-areas').onclick = () => {
  $('show-areas').checked = !$('show-areas').checked;
  $('quick-areas').classList.toggle('active', $('show-areas').checked);
  state.sceneDirty = true;
  draw();
};
$('quick-tools').onclick = () => {
  $('tool-config').hidden = true;
  showPanel('tools', 'layers');
  document.body.classList.add('tools-open');
};
document.addEventListener('pointerdown', (event) => {
  if (!$('tile-context').contains(event.target) && event.target !== canvas) closeContext();
});
$('map').onchange = chooseMap;
$('z').onchange = () => { state.selected.clear(); state.selectedAtom = null; state.selectedNetwork = null;
  state.networkSelectionId++; state.route = []; state.selection = null; state.bounds = null; selectionStatus(); loadView(); };
$('action').onchange = () => { state.route = []; updateActionUI(); draw(); };
for (const button of document.querySelectorAll('.preset')) button.addEventListener('click', () => {
  showPanel('tools', 'edit');
  $('action').value = button.dataset.action;
  updateActionUI();
  $('layer').value = button.dataset.layer;
  $('atom').value = button.dataset.atom;
  $('search').value = '';
  state.route = []; state.selection = null;
  for (const other of document.querySelectorAll('.preset')) other.classList.toggle('active', other === button);
  $('tool-hint').textContent = button.dataset.action === 'route'
    ? `${button.textContent}: click adjacent tiles in order, then Preview edit. Endpoints connect to matching mapped ports when present.`
    : 'Place APC: click one tile, then Preview edit. Connect it to a mapped cable and use Check visible area.';
  catalog(); draw();
});
$('layer').onchange = catalog;
$('search').oninput = () => { clearTimeout(window.catalogTimer); window.catalogTimer = setTimeout(catalog, 200); };
$('zoom').oninput = () => {
  state.cell = +$('zoom').value; scheduleDraw();
  clearTimeout(state.zoomTimer); state.zoomTimer = setTimeout(loadView, 110);
};
for (const name of ['turf', 'objects', 'power', 'atmos', 'disposals', 'apc']) $(`show-${name}`).onchange = () => { state.sceneDirty = true; draw(); };
$('show-areas').onchange = () => { $('quick-areas').classList.toggle('active', $('show-areas').checked); state.sceneDirty = true; draw(); };
for (const button of document.querySelectorAll('[data-edit-layer]')) button.onclick = () => {
  $('layer').value = button.dataset.editLayer;
  for (const other of document.querySelectorAll('[data-edit-layer]')) other.classList.toggle('active', other === button);
  showPanel('tools', 'edit'); catalog();
};
$('edit-cancel').onclick = () => { $('atom-editor').hidden = true; };
const mapSlot = $('top-map-slot');
for (const id of ['map', 'z']) mapSlot.append($(id).closest('label'));
$('topbar-toggle').onclick = () => {
  const collapsed = document.querySelector('.topbar').classList.toggle('collapsed');
  $('topbar-toggle').setAttribute('aria-expanded', String(!collapsed));
  $('topbar-toggle').title = collapsed ? 'Expand map controls' : 'Collapse map controls';
};
function movablePanel(id, handleSelector) {
  const panel = $(id), handle = panel.querySelector(handleSelector);
  const storageKey = `mapstudio-panel-${id}`;
  try {
    const saved = JSON.parse(localStorage.getItem(storageKey) || 'null');
    if (saved) {
      if (saved.width) panel.style.width = `${saved.width}px`;
      if (saved.height && id !== 'topbar') panel.style.height = `${saved.height}px`;
      if (saved.left !== undefined && saved.top !== undefined) {
        panel.style.left = `${Math.max(0, Math.min(saved.left, innerWidth - 80))}px`;
        panel.style.top = `${Math.max(0, Math.min(saved.top, innerHeight - 40))}px`;
        panel.style.right = 'auto'; panel.style.bottom = 'auto'; panel.style.transform = 'none';
      }
    }
  } catch (_) { /* Panel layout can use its default position. */ }
  const save = () => {
    const r = panel.getBoundingClientRect();
    try { localStorage.setItem(storageKey, JSON.stringify({left:r.left,top:r.top,
      width:id === 'topbar' ? undefined : r.width,height:id === 'topbar' ? undefined : r.height})); } catch (_) {}
  };
  handle.addEventListener('pointerdown', (event) => {
    if (event.button !== 0 || event.target.closest('button,input,select,summary')) return;
    const r = panel.getBoundingClientRect(), startX = event.clientX, startY = event.clientY;
    panel.style.left = `${r.left}px`; panel.style.top = `${r.top}px`;
    panel.style.right = 'auto'; panel.style.bottom = 'auto'; panel.style.transform = 'none';
    handle.setPointerCapture(event.pointerId);
    const move = (e) => {
      panel.style.left = `${Math.max(0, Math.min(innerWidth - panel.offsetWidth, r.left + e.clientX - startX))}px`;
      panel.style.top = `${Math.max(0, Math.min(innerHeight - 35, r.top + e.clientY - startY))}px`;
    };
    const done = () => { handle.removeEventListener('pointermove', move); save(); };
    handle.addEventListener('pointermove', move);
    handle.addEventListener('pointerup', done, {once:true});
    handle.addEventListener('pointercancel', done, {once:true});
  });
  handle.addEventListener('dblclick', (event) => {
    if (event.target.closest('button,input,select')) return;
    localStorage.removeItem(storageKey);
    for (const property of ['left','top','right','bottom','width','height','transform']) panel.style[property] = '';
  });
  if (id !== 'topbar') new ResizeObserver(() => { if (!panel.hidden && panel.style.width) save(); }).observe(panel);
}
for (const [id, handle] of [['topbar', 'strong'], ['layer-rail', '.rail-handle'],
  ['tool-palette', '.palette-head'], ['tile-select', '.palette-head'], ['change-review', '#proposal-count']]) {
  if (id === 'topbar') document.querySelector('.topbar').id = 'topbar';
  movablePanel(id, handle);
}
$('tool-palette').append($('tool-config'));
$('tile-select-close').onclick = () => { $('tile-select').hidden = true; };
for (const button of document.querySelectorAll('[data-mode]')) button.onclick = () => { setMode(button.dataset.mode); openPalette(); };
for (const button of document.querySelectorAll('[data-layer-button]')) {
  button.onclick = () => { selectLayer(button.dataset.layerButton); };
  button.oncontextmenu = (event) => {
    event.preventDefault();
    document.querySelector(`[data-layer-eye="${button.dataset.layerButton}"]`).click();
  };
}
for (const eye of document.querySelectorAll('[data-layer-eye]')) {
  eye.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12s3.7-6 10-6 10 6 10 6-3.7 6-10 6S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/><path class="eye-slash" d="M3 21 21 3"/></svg>';
  eye.onclick = () => {
    const layer = eye.dataset.layerEye;
    const checkbox = $(`show-${layer === 'area' ? 'areas' : layer}`);
    checkbox.checked = !checkbox.checked;
    if (state.temporaryLayer === layer) state.temporaryLayer = null;
    checkbox.dispatchEvent(new Event('change'));
    syncLayerRail();
  };
}
$('brush-type').oninput = () => {
  const value = $('brush-type').value.trim();
  if (value.startsWith('/')) {
    $('atom').value = value;
    clearTimeout(state.warmPowerTimer);
    state.warmPowerTimer = setTimeout(warmPowerSprites,150);
  }
  else { $('search').value = value; clearTimeout(state.brushSearchTimer); state.brushSearchTimer = setTimeout(catalog, 180); }
};
for (const [id, action] of [['network-join','network_join'],['network-cross','network_cross']])
  $(id).onclick = () => {
    const point = state.selectedAtom?.point || state.lastPoint;
    if (!point) { showError('Click a network tile first.'); return; }
    const atom = action === 'network_split' ? state.selectedAtom?.atom : $('atom').value.trim();
    if (!atom) { showError('Pick a network segment or type first.'); return; }
    previewOperation({action, at:point, layer:state.activeLayer, atom});
  };
setMode('select'); selectLayer('turf');
window.addEventListener('resize', draw);
document.addEventListener('keydown', (event) => {
  if (event.code === 'Space' && !['INPUT', 'SELECT', 'TEXTAREA'].includes(document.activeElement?.tagName)) { event.preventDefault(); state.spaceHeld = true; }
  if (['INPUT', 'SELECT', 'TEXTAREA'].includes(document.activeElement?.tagName)) return;
  if (event.key.toLowerCase() === 's' && !event.ctrlKey && !event.metaKey) { state.pickHeld = true; event.preventDefault(); }
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'z') {
    event.preventDefault();
    if (state.preview) $('discard').click();
    else if (state.lastCommit) $('undo').click();
    else if (state.selectionHistory.length) { state.selected = state.selectionHistory.pop(); if (!state.selectionHistory.length) state.lastCommit = !!state.canUndoCommit; selectionStatus(); draw(); }
    else if (state.canUndoCommit) $('undo').click();
    else status('Nothing to undo.');
    return;
  }
  if (event.key === 'Escape') $('clear').click();
  const shift = { ArrowLeft: [-8, 0], ArrowRight: [8, 0], ArrowUp: [0, 8], ArrowDown: [0, -8] }[event.key];
  if (shift) {
    event.preventDefault();
    state.camera.x += shift[0]; state.camera.y += shift[1]; clampCamera();
    loadView();
  }
});
document.addEventListener('keyup', (event) => { if (event.code === 'Space') state.spaceHeld = false; if (event.key.toLowerCase() === 's') state.pickHeld = false; });
window.addEventListener('blur', () => { state.pickHeld = false; state.spaceHeld = false; });
api('maps').then((data) => {
  $('map').replaceChildren(...data.maps.map((path) => { const option = document.createElement('option'); option.value = path; option.textContent = path; return option; }));
  $('map').value = data.maps.find((path) => path.includes('southern_cross-1.dmm')) || data.maps[0];
  chooseMap();
}).catch((error) => status(error.message));
setInterval(async () => {
  try {
    const latest = await api('activity');
    if (latest.preview_id && latest.map === state.map && latest.preview_id !== state.preview?.preview_id && latest.preview_id !== state.dismissedPreview) {
      showPreview(latest); status('An agent proposed a map edit. Review and save it here.');
    }
  } catch { /* Server connection errors are shown by direct actions. */ }
}, 2000);
