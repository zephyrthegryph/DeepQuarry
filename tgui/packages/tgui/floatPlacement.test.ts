import { describe, expect, it } from 'bun:test';
import {
  dragFrame,
  floatAtText,
  floatSize,
  parseFloatAt,
  placeUnder,
  underPointer,
} from './floatPlacement';

describe('float text', () => {
  it('round trips a point with and without a size', () => {
    expect(parseFloatAt(floatAtText([554, 723]))).toEqual({
      point: [554, 723],
      size: null,
    });
    expect(parseFloatAt(floatAtText([554, 723], [600, 480]))).toEqual({
      point: [554, 723],
      size: [600, 480],
    });
  });

  it('refuses anything else', () => {
    expect(parseFloatAt(null)).toBeNull();
    expect(parseFloatAt('1,2,3')).toBeNull();
    expect(parseFloatAt('a,b')).toBeNull();
    expect(parseFloatAt('1,2,0,5')?.size).toBeNull();
  });
});

describe('placement', () => {
  it('puts the pointer on the middle of the title bar', () => {
    expect(placeUnder([554, 723], 520)).toEqual([294, 707]);
  });

  it('centres on the size the text carries before the window own', () => {
    expect(underPointer('554,723,400,300', [520, 640])).toEqual([354, 707]);
    expect(underPointer('554,723', [520, 640])).toEqual([294, 707]);
    expect(underPointer(null, [520, 640])).toBeNull();
  });
});

describe('floatSize', () => {
  it('keeps the docked size in physical pixels', () => {
    expect(floatSize({ w: 320, h: 500 }, 1.5)).toEqual([480, 750]);
  });

  it('never opens smaller than a usable window or bigger than the screen', () => {
    expect(floatSize({ w: 20, h: 22 }, 1)).toEqual([150, 120]);
    expect(floatSize({ w: 5000, h: 5000 }, 2, [2560, 1440])).toEqual([
      2560, 1440,
    ]);
  });
});

describe('dragFrame', () => {
  it('moves only the place while the size holds', () => {
    expect(dragFrame([10.4, 20.6], [500, 400], [502, 399])).toEqual({
      pos: '10,21',
      drift: false,
    });
  });

  it('puts the held size back when the window was rescaled under the drag', () => {
    expect(dragFrame([10, 20], [500, 400], [625, 500])).toEqual({
      pos: '10,20',
      size: '500x400',
      drift: true,
    });
  });
});
