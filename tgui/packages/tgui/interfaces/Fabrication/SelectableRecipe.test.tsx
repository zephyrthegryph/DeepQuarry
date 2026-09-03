import { afterEach, describe, expect, test } from 'bun:test';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { ProductConfigurator } from './SelectableRecipe';
import type { Design, MaterialChoice } from './Types';

afterEach(cleanup);

const design: Design = {
  name: 'Pressure Pipe',
  desc: 'A standard pressure pipe.',
  id: 'pressure_pipe',
  icon: 'design32x32 pressure_pipe',
  categories: ['/Initial'],
  cost: {},
  materialConfigurable: 1,
  materialProfile: 'pressure service',
  materialSlots: [
    {
      role: 'structure',
      label: 'Pressure shell',
      amount: 100,
      defaultMaterial: 'processed_alpha',
      optional: 0,
      description: 'Controls pressure strength.',
    },
  ],
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

describe('material construction workbench', () => {
  test('survives live inventory changes and builds with the valid fallback id', () => {
    const builds: Array<[Record<string, string>, number]> = [];
    const alpha = choice('processed_alpha', 'Alpha alloy');
    const beta = choice('processed_beta', 'Beta alloy');
    const view = render(
      <ProductConfigurator
        design={design}
        available={{ processed_alpha: 1000, processed_beta: 1000 }}
        materialChoices={[alpha, beta]}
        SHEET_MATERIAL_AMOUNT={100}
        onBuild={(id, amount) => builds.push([id, amount])}
      />,
    );

    view.rerender(
      <ProductConfigurator
        design={design}
        available={{ processed_beta: 1000 }}
        materialChoices={[beta]}
        SHEET_MATERIAL_AMOUNT={100}
        onBuild={(id, amount) => builds.push([id, amount])}
      />,
    );
    fireEvent.click(screen.getByText('Fabricate').closest('.Button')!);
    expect(builds).toEqual([[{ structure: 'processed_beta' }, 1]]);
  });

  test('keeps the normal product simple and reveals customization on demand', () => {
    render(
      <ProductConfigurator
        design={design}
        available={{ processed_alpha: 1000 }}
        materialChoices={[choice('processed_alpha', 'Alpha alloy')]}
        SHEET_MATERIAL_AMOUNT={100}
        onBuild={() => undefined}
      />,
    );

    expect(screen.getByText('Pressure shell')).toBeDefined();
    expect(
      screen.queryByPlaceholderText('Search loaded materials...'),
    ).toBeNull();
    fireEvent.click(screen.getByText('Custom').closest('.Button')!);
    fireEvent.click(screen.getByText('Pressure shell').closest('.Button')!);
    expect(screen.getByText('Pressure shell')).toBeDefined();
    expect(screen.getByText('Controls pressure strength.')).toBeDefined();
    expect(
      screen.getByPlaceholderText('Search loaded materials...'),
    ).toBeDefined();
  });
});
