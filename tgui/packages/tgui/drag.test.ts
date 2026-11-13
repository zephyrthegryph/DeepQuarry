import { describe, expect, it } from 'bun:test';
import { dropNeedsCheck } from './drag';

const column = { x: 1600, y: 0, w: 320, h: 900 };

describe('dropNeedsCheck', () => {
  it('asks the server only for a drop over the column', () => {
    expect(dropNeedsCheck(column, [1700, 400])).toBe(true);
    expect(dropNeedsCheck(column, [800, 400])).toBe(false);
    expect(dropNeedsCheck(column, [1700, 950])).toBe(false);
  });

  it('leaves it to the page when the column cannot be measured', () => {
    expect(dropNeedsCheck(null, [800, 400])).toBe(true);
  });
});
