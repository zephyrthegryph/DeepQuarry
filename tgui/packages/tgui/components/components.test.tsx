import { afterEach, describe, expect, it } from 'bun:test';
import { cleanup, render } from '@testing-library/react';
import { LabeledList } from 'tgui-core/components';
import { Label } from './Label';
import { StatBar } from './StatBar';
import { YesNo } from './YesNo';

afterEach(cleanup);

describe('shared window components', () => {
  it('StatBar renders a labelled gauge', () => {
    const { container } = render(
      <LabeledList>
        <StatBar label="Charge" value={0.5}>
          50%
        </StatBar>
      </LabeledList>,
    );
    expect(container.textContent).toContain('Charge');
    expect(container.textContent).toContain('50%');
    expect(container.querySelector('.ProgressBar')).not.toBeNull();
  });

  it('Label uses the label colour and passes Box props through', () => {
    const { container } = render(<Label italic>hint</Label>);
    const node = container.firstElementChild as HTMLElement;
    expect(node.className).toContain('color-label');
    expect(node.textContent).toBe('hint');
  });

  it('YesNo colours by truth and honours custom words', () => {
    const on = render(<YesNo value={1} yes="Armed" />).container;
    expect(on.querySelector('.color-good')?.textContent).toBe('Armed');
    cleanup();
    const off = render(<YesNo value={0} />).container;
    expect(off.querySelector('.color-bad')?.textContent).toBe('No');
  });
});
