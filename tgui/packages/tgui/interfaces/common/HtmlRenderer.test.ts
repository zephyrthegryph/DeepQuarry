import { describe, expect, it } from 'bun:test';

import {
  isSafeHtmlImageSrc,
  safeHtmlColor,
  safeHtmlFontFace,
  safeHtmlStyle,
} from './HtmlRenderer';

describe('HtmlRenderer sanitizers', () => {
  it('accepts only local or inert raster image sources', () => {
    expect(isSafeHtmlImageSrc('icons/ui/example.png')).toBe(true);
    expect(isSafeHtmlImageSrc('data:image/png;base64,QUJDRA==')).toBe(true);
    expect(isSafeHtmlImageSrc('javascript:alert(1)')).toBe(false);
    expect(isSafeHtmlImageSrc('data:image/svg+xml,<svg onload=alert(1)>')).toBe(
      false,
    );
    expect(isSafeHtmlImageSrc('https://attacker.invalid/pixel.png')).toBe(
      false,
    );
  });

  it('rejects CSS-bearing color and font values', () => {
    expect(safeHtmlColor('#12abEF')).toBe('#12abEF');
    expect(safeHtmlColor('red')).toBe('red');
    expect(safeHtmlColor('red; background:url(x)')).toBeUndefined();
    expect(safeHtmlFontFace('Segoe Script')).toBe('Segoe Script');
    expect(safeHtmlFontFace('x);background:url(x)')).toBeUndefined();
  });

  it('keeps only listed style properties with checked values', () => {
    expect(safeHtmlStyle('background:#f4c7c3')).toEqual({
      backgroundColor: '#f4c7c3',
    });
    expect(
      safeHtmlStyle('background:#111;color:#ddd;font-family:monospace'),
    ).toEqual({
      backgroundColor: '#111',
      color: '#ddd',
      fontFamily: 'monospace',
    });
    expect(safeHtmlStyle('font-size:10px;line-height:10px')).toEqual({
      fontSize: '10px',
      lineHeight: '10px',
    });
    expect(safeHtmlStyle('background:url(x)')).toBeUndefined();
    expect(safeHtmlStyle('position:fixed;top:0')).toBeUndefined();
    expect(safeHtmlStyle('color:red;width:expression(alert(1))')).toEqual({
      color: 'red',
    });
  });
});
