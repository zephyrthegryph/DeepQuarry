import { afterEach, describe, expect, it } from 'bun:test';
import { act, cleanup, render } from '@testing-library/react';
import { gameDataAtom, store } from '../events/store';
import fixture from './__fixtures__/windows/StationWiki.json';
import {
  buildTree,
  calloutOf,
  deptOf,
  plainText,
  StationWiki,
  searchIndex,
} from './StationWiki';

afterEach(cleanup);

type Row = [string, string, string, string];
const index = fixture.index as Row[];

describe('StationWiki', () => {
  it('renders the fixture article with its infobox, callouts, chips and related list', () => {
    store.set(gameDataAtom, fixture);
    act(() => render(<StationWiki />));
    const root = document.body;
    expect(root.querySelector('.StationWiki__title')?.textContent).toBe(
      'Concussion',
    );
    // The first labelled facts move into the infobox, not the body.
    const infobox = root.querySelector('.StationWiki__infobox');
    expect(infobox?.textContent).toContain('Self-resolving');
    expect(
      root.querySelectorAll('.StationWiki__body > .StationWiki__facts').length,
    ).toBe(0);
    expect(root.querySelector('.StationWiki__callout--danger')).toBeTruthy();
    expect(root.querySelector('.StationWiki__callout--warning')).toBeTruthy();
    expect(root.querySelector('.StationWiki__chip--good')).toBeTruthy();
    expect(root.querySelector('.StationWiki__crumbs')?.textContent).toContain(
      'Neurological',
    );
    expect(root.querySelector('.StationWiki__related')?.textContent).toContain(
      'Skull fracture',
    );
  });

  it('opens a section landing page from a breadcrumb', () => {
    store.set(gameDataAtom, fixture);
    act(() => render(<StationWiki />));
    const crumbs = document.body.querySelectorAll('.StationWiki__crumb');
    act(() => (crumbs[1] as HTMLElement).click());
    expect(
      document.body.querySelector('.StationWiki__title')?.textContent,
    ).toContain('Medical');
    expect(
      document.body.querySelectorAll('.StationWiki__card').length,
    ).toBeGreaterThan(3);
  });

  it('counts articles per section', () => {
    const tree = buildTree(index);
    expect(tree.count).toBe(index.length);
    const medical = tree.children.get('Medical');
    expect(medical?.count).toBe(
      index.filter((row) => row[2].startsWith('Medical')).length,
    );
  });

  it('ranks title matches first and reads markup out of snippets', () => {
    const results = searchIndex(index, 'bleed');
    expect(results[0][1].toLowerCase()).toContain('bleed');
    const titles = new Map(
      index.map((row) => [row[0], row[1]] as [string, string]),
    );
    expect(
      plainText('See [[med/cond/concussion]] and [[x|that]]', titles),
    ).toBe('See Concussion and that');
  });

  it('maps tones to callouts and paths to departments', () => {
    expect(calloutOf('good').kind).toBe('tip');
    expect(calloutOf('bad').kind).toBe('danger');
    expect(calloutOf('average').kind).toBe('warning');
    expect(calloutOf(null).kind).toBe('info');
    expect(deptOf('Medical/Drugs').icon).toBe('kit-medical');
    expect(deptOf('Nowhere').icon).toBe('folder');
  });
});
