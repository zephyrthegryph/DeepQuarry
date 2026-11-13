import { describe, expect, it } from 'bun:test';
import { FloatFollow } from './floatDrag';

function make(size: [number, number] = [400, 300]) {
  const sent: [string, string][] = [];
  const done: string[] = [];
  const log: string[] = [];
  const follow = new FloatFollow(
    size,
    [1000, 500],
    (id, props) => sent.push([id, props.pos]),
    (message) => log.push(message),
    (id) => done.push(id),
  );
  return { follow, sent, done, log };
}

describe('FloatFollow', () => {
  it('sends nothing until the window reports itself, then catches up to the pointer', () => {
    const { follow, sent } = make();
    follow.move([1010, 520]);
    follow.move([1100, 560]);
    expect(sent).toEqual([]);
    follow.adopt('window-3');
    expect(sent).toEqual([['window-3', '900,544']]);
  });

  it('follows both axes, keeping the pointer on the title bar', () => {
    const { follow, sent } = make();
    follow.adopt('w');
    follow.move([1000, 300]);
    follow.move([800, 900]);
    expect(sent.map((s) => s[1])).toEqual(['800,484', '800,284', '600,884']);
  });

  it('does not repeat a place', () => {
    const { follow, sent } = make();
    follow.adopt('w');
    follow.move([1000, 500]);
    follow.move([1000, 500]);
    expect(sent).toHaveLength(1);
  });

  it('places the window at the release and then reports done once', () => {
    const { follow, sent, done } = make();
    follow.adopt('w');
    follow.release([700, 650]);
    expect(sent.at(-1)).toEqual(['w', '500,634']);
    expect(done).toEqual(['w']);
    follow.move([1, 1]);
    follow.adopt('other');
    expect(sent).toHaveLength(2);
    expect(done).toEqual(['w']);
  });

  it('finishes at the final place when the window reports after the release', () => {
    const { follow, sent, done } = make();
    follow.release([700, 650]);
    expect(done).toEqual([]);
    follow.adopt('late');
    expect(sent).toEqual([['late', '500,634']]);
    expect(done).toEqual(['late']);
  });
});
