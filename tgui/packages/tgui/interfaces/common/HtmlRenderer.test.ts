import { describe, expect, it } from 'bun:test';

import {
  isSafeHtmlImageSrc,
  safeHtmlColor,
  safeHtmlFontFace,
} from './HtmlRenderer';

describe('HtmlRenderer sanitizers', () => {
  it('accepts only local or inert raster image sources', () => {
    expect(isSafeHtmlImageSrc('icons/ui/example.png')).toBe(true);
    expect(isSafeHtmlImageSrc('data:image/png;base64,QUJDRA==')).toBe(true);
    expect(isSafeHtmlImageSrc('javascript:alert(1)')).toBe(false);
    expect(
      isSafeHtmlImageSrc('data:image/svg+xml,<svg onload=alert(1)>'),
    ).toBe(false);
    expect(isSafeHtmlImageSrc('https://attacker.invalid/pixel.png')).toBe(false);
  });

  it('rejects CSS-bearing color and font values', () => {
    expect(safeHtmlColor('#12abEF')).toBe('#12abEF');
    expect(safeHtmlColor('red')).toBe('red');
    expect(safeHtmlColor('red; background:url(x)')).toBeUndefined();
    expect(safeHtmlFontFace('Segoe Script')).toBe('Segoe Script');
    expect(safeHtmlFontFace('x);background:url(x)')).toBeUndefined();
  });
});
