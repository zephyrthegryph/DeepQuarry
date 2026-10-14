const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

// Exercise the production drag functions with pointer samples that cross a
// cardinal edge before entering a diagonal tile, as real browser events do.
const source = fs.readFileSync(`${__dirname}/app.js`, 'utf8');
const block = (start, end) => source.slice(source.indexOf(start), source.indexOf(end));
const state = {activeLayer:'power',strokeMode:'place',cell:100};
const context = vm.createContext({state, Math});
vm.runInContext(block('function appendStroke(', 'function scheduleNetworkDraft(') +
  block('function updateStrokeCornerIntent(', 'function networkEndTarget('), context);
const anchor = {x:0,y:0,z:1}, east={x:1,y:0,z:1};
const northeast={x:1,y:1,z:1};
function reset(stroke) {
  Object.assign(state,{stroke:[...stroke],strokePointerOrigin:{x:0,y:0},
    strokePointerSample:{x:.97,y:0},strokeSegmentStartPointer:{x:.97,y:0},
    strokeCornerEntry:false,strokeCardinalCommitted:false,strokeDiagonalRetreat:null});
}
function move(point,x,y) {
  const target=context.strokePointAtPointer({clientX:x*100,clientY:-y*100},point);
  context.appendStroke(target);
  state.strokePointerSample={x,y};
}

reset([anchor,east]);
move(northeast,1.08,.12);
assert.deepEqual(state.stroke.map(({x,y})=>[x,y]),[[0,0],[1,1]],'quick corner makes a diagonal');

reset([anchor,east]);
move(northeast,1.08,.04);
assert.deepEqual(state.stroke.map(({x,y})=>[x,y]),[[0,0],[1,0],[1,1]],
  'small sideways jitter does not replace a cardinal segment');

reset([anchor,east]);
move(east,1.3,0);
move(northeast,1.3,1.05);
assert.deepEqual(state.stroke.map(({x,y})=>[x,y]),[[0,0],[1,0],[1,1]],
  'a committed cardinal turn remains cardinal');

reset([anchor,northeast]);
move(east,1.05,.8);
move(anchor,.95,.95);
assert.deepEqual(state.stroke.map(({x,y})=>[x,y]),[[0,0]],
  'diagonal retreat through a side tile removes both transient steps');

console.log('wire gesture checks passed');
