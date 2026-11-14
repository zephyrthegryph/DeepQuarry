import { describe, expect, it } from 'bun:test';
import { dropNeedsCheck, overlapsColumn } from './drag';

const column = { x: 1600, y: 0, w: 320, h: 900 };

describe('overlapsColumn', () => {
  it('docks a small window that is inside the column', () => {
    expect(overlapsColumn(column, { x: 1620, y: 100, w: 250, h: 300 })).toBe(
      true,
    );
  });

  it('does not dock a small window only half over the column', () => {
    expect(overlapsColumn(column, { x: 1475, y: 100, w: 250, h: 300 })).toBe(
      false,
    );
  });

  it('does not dock a big window whose edge just entered the column', () => {
    expect(overlapsColumn(column, { x: 1000, y: 50, w: 700, h: 700 })).toBe(
      false,
    );
    expect(overlapsColumn(column, { x: 1000, y: 50, w: 1000, h: 700 })).toBe(
      false,
    );
  });

  it('docks a window once 60% of its width is over the column', () => {
    expect(overlapsColumn(column, { x: 1500, y: 50, w: 400, h: 700 })).toBe(
      true,
    );
  });

  it('never docks a window clear of the column', () => {
    expect(overlapsColumn(column, { x: 100, y: 100, w: 300, h: 300 })).toBe(
      false,
    );
    expect(overlapsColumn(column, { x: 1700, y: 950, w: 200, h: 200 })).toBe(
      false,
    );
  });
});

describe('dropNeedsCheck', () => {
  it('asks the server only for a window mostly over the column', () => {
    expect(dropNeedsCheck(column, { x: 1620, y: 100, w: 250, h: 300 })).toBe(
      true,
    );
    expect(dropNeedsCheck(column, { x: 800, y: 100, w: 250, h: 300 })).toBe(
      false,
    );
  });

  it('leaves it to the page when the column cannot be measured', () => {
    expect(dropNeedsCheck(null, { x: 800, y: 100, w: 250, h: 300 })).toBe(true);
  });
});
