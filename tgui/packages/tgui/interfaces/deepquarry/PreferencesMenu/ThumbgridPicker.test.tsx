import { afterEach, describe, expect, it } from 'bun:test';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { selectedChoice, ThumbgridPicker, thumbLayers } from './PrefWidget';
import type { PrefWidgetItem } from './types';

afterEach(cleanup);

const item = (value: unknown): PrefWidgetItem => ({
  type: 'widget',
  key: 'ear_style',
  widget: 'thumbgrid',
  value,
  props: {},
  choices: { '': 'None', fox: 'Fox', cat: 'Cat' },
  thumbnails: {},
});

const optionButton = (label: string) =>
  screen
    .getAllByText(label)
    .map((node) => node.closest('.Button') ?? node)
    .find((node) => node.closest('[style*="max-height"]'));

describe('ThumbgridPicker', () => {
  it('stays open after a pick, so styles can be compared', () => {
    const picks: string[] = [];
    render(
      <ThumbgridPicker item={item('fox')} onPick={(v) => picks.push(v)} />,
    );
    fireEvent.click(screen.getByText('Change'));
    const cat = optionButton('Cat');
    expect(cat).toBeTruthy();
    fireEvent.click(cat as Element);
    expect(picks).toEqual(['cat']);
    expect(screen.getByPlaceholderText('Search…')).toBeTruthy();
    expect(screen.getByText('Close')).toBeTruthy();
  });

  it('closes on its Close button, Escape and a click outside', () => {
    render(
      <div>
        <span>elsewhere</span>
        <ThumbgridPicker item={item('fox')} onPick={() => {}} />
      </div>,
    );
    fireEvent.click(screen.getByText('Change'));
    fireEvent.click(screen.getByText('Close'));
    expect(screen.queryByPlaceholderText('Search…')).toBeNull();

    fireEvent.click(screen.getByText('Change'));
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.queryByPlaceholderText('Search…')).toBeNull();

    fireEvent.click(screen.getByText('Change'));
    fireEvent.mouseDown(screen.getByText('elsewhere'));
    expect(screen.queryByPlaceholderText('Search…')).toBeNull();
  });

  it('highlights the current style, None included', () => {
    render(<ThumbgridPicker item={item('none')} onPick={() => {}} />);
    fireEvent.click(screen.getByText('Change'));
    const none = optionButton('None');
    expect(none?.className).toContain('selected');
    expect(optionButton('Fox')?.className).not.toContain('selected');
  });
});

describe('selectedChoice', () => {
  const choices: Array<[string, string]> = [
    ['', 'None'],
    ['fox', 'Fox'],
  ];
  it('selects None for a blank or "none" value', () => {
    expect(selectedChoice(choices, null)).toBe('');
    expect(selectedChoice(choices, 'none')).toBe('');
    expect(selectedChoice(choices, 'fox')).toBe('fox');
  });
});

describe('thumbLayers', () => {
  const body = [{ icon: 'body.dmi', icon_state: 'torso_m', color: '#c8a283' }];
  it('draws None as the body and every style on it', () => {
    const thumbs = {
      '': { layers: body, base: 1 },
      fox: { icon: 'ears.dmi', icon_state: 'fox' },
    };
    expect(thumbLayers(thumbs, '')).toEqual(body);
    expect(thumbLayers(thumbs, 'fox')).toEqual([
      ...body,
      { icon: 'ears.dmi', icon_state: 'fox', color: '#ffffff' },
    ]);
  });
  it('draws a style alone when the picker has no body', () => {
    expect(
      thumbLayers({ fox: { icon: 'e.dmi', icon_state: 'f' } }, 'fox'),
    ).toEqual([{ icon: 'e.dmi', icon_state: 'f', color: '#ffffff' }]);
    expect(thumbLayers({}, 'fox')).toBeNull();
  });
});
