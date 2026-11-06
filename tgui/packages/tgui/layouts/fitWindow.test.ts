import { describe, expect, it } from 'bun:test';
import { FIT_TOLERANCE, fitOverflow, measureContentBottom } from './fitWindow';

describe('fitOverflow', () => {
  it('is zero when the content fits', () => {
    expect(fitOverflow(120, 168)).toBe(0);
    expect(fitOverflow(168, 168)).toBe(0);
  });
  it('ignores sub-pixel noise', () => {
    expect(fitOverflow(168 + FIT_TOLERANCE, 168)).toBe(0);
  });
  it('reports the clipped height rounded up', () => {
    expect(fitOverflow(230.2, 168)).toBe(63);
  });
});

function box(bottom: number, style: Record<string, string> = {}, tag = 'div') {
  const el = document.createElement(tag);
  Object.assign(el.style, style);
  el.getBoundingClientRect = () =>
    ({
      top: 0,
      bottom,
      height: bottom,
      width: 100,
      left: 0,
      right: 100,
    }) as DOMRect;
  return el;
}

describe('measureContentBottom', () => {
  it('finds a child that overflows its parent and adds ancestor padding', () => {
    const root = box(168, { paddingBottom: '7px' });
    const section = box(168, { paddingBottom: '5px' });
    const message = box(300);
    section.appendChild(message);
    root.appendChild(section);
    document.body.appendChild(root);
    // message bottom 300 + section padding 5 + root padding 7
    expect(measureContentBottom(root)).toBe(312);
    root.remove();
  });
  it('does not exceed the window when nothing overflows', () => {
    const root = box(168, { paddingBottom: '7px' });
    const inner = box(100);
    root.appendChild(inner);
    document.body.appendChild(root);
    expect(fitOverflow(measureContentBottom(root), 168)).toBe(0);
    root.remove();
  });
});
