import { describe, expect, it } from 'bun:test';
import { FIT_TOLERANCE, fitOverflow, measureNaturalBottom } from './fitWindow';

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

describe('measureNaturalBottom', () => {
  // A root whose height follows the window unless released to auto, like
  // .Window__contentPadding with a fill Section inside.
  function fillRoot(windowHeight: number, naturalHeight: number) {
    const root = document.createElement('div');
    Object.assign(root.style, { height: '100px', marginBottom: '8px' });
    root.getBoundingClientRect = () => {
      const height =
        root.style.height === 'auto' ? naturalHeight : windowHeight;
      return {
        top: 40,
        bottom: 40 + height,
        height,
        width: 100,
        left: 0,
        right: 100,
      } as DOMRect;
    };
    document.body.appendChild(root);
    return root;
  }

  it('reads the natural height plus the bottom margin', () => {
    const root = fillRoot(168, 130);
    expect(measureNaturalBottom(root)).toBe(40 + 130 + 8);
    root.remove();
  });
  it('is independent of the window height, so growing cannot loop', () => {
    const results = [168, 240, 408, 900].map((h) => {
      const root = fillRoot(h, 130);
      const bottom = measureNaturalBottom(root);
      root.remove();
      return bottom;
    });
    expect(new Set(results).size).toBe(1);
  });
  it('settles after one grow: the fit it asks for satisfies itself', () => {
    const root = fillRoot(168, 300);
    let inner = 168;
    for (let i = 0; i < 5; i++) {
      inner += fitOverflow(measureNaturalBottom(root), inner);
    }
    expect(inner).toBe(40 + 300 + 8);
    expect(fitOverflow(measureNaturalBottom(root), inner)).toBe(0);
    root.remove();
  });
  it('restores the inline styles it touched', () => {
    const root = fillRoot(168, 130);
    const list = document.createElement('div');
    list.style.overflowY = 'auto';
    root.appendChild(list);
    measureNaturalBottom(root);
    expect(root.style.height).toBe('100px');
    expect(list.style.maxHeight).toBe('');
    root.remove();
  });
});
