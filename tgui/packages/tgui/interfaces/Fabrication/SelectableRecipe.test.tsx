import { afterEach, describe, expect, test } from 'bun:test';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import type { Design, MaterialChoice } from './Types';
import { SelectableRecipe } from './SelectableRecipe';

afterEach(cleanup);

const design: Design = {
  name: 'Material Pressure Pipe',
  desc: 'A selected-material pipe.',
  id: 'material_pipe',
  icon: 'design32x32 material_pipe',
  categories: ['/Initial'],
  cost: {},
  materialSelectable: 1,
  selectableAmount: 100,
  materialProfile: 'pressure service',
};

const choice = (id: string, label: string): MaterialChoice => ({
  id,
  label,
  sheets: 10,
  color: '#ffffff',
  layers: [],
  responses: ['thermoelectric generation'],
  hardness: 80,
  density: 70,
  integrity: 75,
  elasticity: 60,
  brittleness: 20,
  toughness: 85,
  conductivity: 90,
  heatResistance: 65,
  thermalInsulation: 40,
  corrosionResistance: 88,
  pressureLimit: 42,
});

describe('material-selectable fabrication interaction', () => {
  test('survives live inventory changes and builds with the valid fallback id', () => {
    const builds: Array<[string, number]> = [];
    const alpha = choice('processed_alpha', 'Alpha alloy');
    const beta = choice('processed_beta', 'Beta alloy');
    const view = render(
      <SelectableRecipe
        design={design}
        available={{ processed_alpha: 1000, processed_beta: 1000 }}
        materialChoices={[alpha, beta]}
        SHEET_MATERIAL_AMOUNT={100}
        onBuild={(id, amount) => builds.push([id, amount])}
      />,
    );

    view.rerender(
      <SelectableRecipe
        design={design}
        available={{ processed_beta: 1000 }}
        materialChoices={[beta]}
        SHEET_MATERIAL_AMOUNT={100}
        onBuild={(id, amount) => builds.push([id, amount])}
      />,
    );
    fireEvent.click(view.container.querySelector('.FabricatorRecipe__Title')!);
    expect(builds).toEqual([['processed_beta', 1]]);
  });

  test('reveals only product-relevant diagnostics on demand', () => {
    render(
      <SelectableRecipe
        design={design}
        available={{ processed_alpha: 1000 }}
        materialChoices={[choice('processed_alpha', 'Alpha alloy')]}
        SHEET_MATERIAL_AMOUNT={100}
        onBuild={() => undefined}
      />,
    );

    expect(screen.queryByText('Strength')).toBeNull();
    fireEvent.click(screen.getByLabelText('Material details'));
    expect(screen.getByText('Strength')).toBeDefined();
    expect(screen.getByText(/Pressure geometry: 42 atm/)).toBeDefined();
    expect(screen.queryByText('Conductivity')).toBeNull();
  });
});
