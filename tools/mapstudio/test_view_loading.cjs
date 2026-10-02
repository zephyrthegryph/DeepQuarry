const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync(`${__dirname}/app.js`, 'utf8');
const start = source.indexOf('function uncoveredViewRects(');
const end = source.indexOf('async function loadView(', start);
const context = vm.createContext({});
vm.runInContext(source.slice(start, end), context);

const previous = {x1:10,y1:10,x2:20,y2:20,z:1};
const next = {x1:15,y1:14,x2:25,y2:24,z:1};
const uncovered = context.uncoveredViewRects(next, previous);
const cells = new Set();
for (const rect of uncovered) for (let x=rect.x1;x<=rect.x2;x++)
  for (let y=rect.y1;y<=rect.y2;y++) {
    const cell=`${x},${y}`;
    assert(!cells.has(cell), 'uncovered strips must not overlap');
    cells.add(cell);
  }
for (let x=next.x1;x<=next.x2;x++) for (let y=next.y1;y<=next.y2;y++)
  assert.equal(cells.has(`${x},${y}`), x>previous.x2 || y>previous.y2);
assert.equal(cells.size, 79);
assert.equal(context.uncoveredViewRects(previous, previous).length, 0);
assert.equal(context.uncoveredViewRects(next, {...previous,z:2}).length, 1);
const wide = context.boundedViewRects([{x1:1,x2:190,y1:1,y2:110,z:1}]);
assert.equal(wide.reduce((sum, region) => sum +
  (region.x2-region.x1+1)*(region.y2-region.y1+1), 0), 190*110);
assert(wide.every((region) => (region.x2-region.x1+1)*(region.y2-region.y1+1) <= 12000));
console.log('view loading checks passed');
