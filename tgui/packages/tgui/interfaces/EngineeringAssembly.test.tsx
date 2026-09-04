import { afterEach, expect, test } from 'bun:test';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { cleanup, render, screen } from '@testing-library/react';
import { gameDataAtom, store } from '../events/store';
import { EngineeringAssembly } from './EngineeringAssembly';

afterEach(cleanup);

test('engineering diagnostics presents operating energy and independent installed parts', async () => {
  store.set(gameDataAtom, {
    status: 'Nominal',
    temperature: 248,
    buffer: 17500,
    input: 37500,
    output: 30000,
    lossEnergy: 450000,
    configuration: 3,
    liner: 100,
    shell: 96,
    fatigue: 4,
    monitoring: true,
    limiting: 'Thermal buffer has 32,500 J remaining',
    emitter: { output: 1, cadence: 1, stored: 180000, active: true },
    parts: [
      {
        role: 'structure',
        material: 'Steel',
        meltingPoint: 1810,
        corrosion: 65,
      },
      {
        role: 'conductor',
        material: 'Cryogenic copper alloy',
        meltingPoint: 1300,
        corrosion: 75,
      },
      { role: 'emitter', material: 'Glass', meltingPoint: 1700, corrosion: 90 },
      {
        role: 'optical',
        material: 'Quartz',
        meltingPoint: 1943,
        corrosion: 90,
      },
      {
        role: 'thermal buffer',
        material: 'Phase-treated alloy',
        meltingPoint: 1100,
        corrosion: 70,
      },
      {
        role: 'insulation',
        material: 'Glass',
        meltingPoint: 1700,
        corrosion: 90,
      },
    ],
    reading: {
      name: 'Emitter',
      assembly: 'ME-1042',
      duration: 60,
      minimum_output_watts: 30000,
      maximum_temperature_k: 250,
      efficiency: 0.8,
    },
  });
  const view = render(<EngineeringAssembly />);
  expect(screen.getByText('37,500 W in / 30,000 W delivered')).toBeDefined();
  expect(screen.getByText('Cryogenic copper alloy')).toBeDefined();
  expect(screen.getByText('Pulse energy:')).toBeDefined();
  expect(screen.queryByText('Certify')).toBeNull();
  expect(screen.getByText(/print the reading at a photocopier/)).toBeDefined();

  if (process.env.ENGINEERING_PREVIEW) {
    const { compileAsync } = await import('sass-embedded');
    const css = (
      await compileAsync('packages/tgui/styles/main.scss', {
        loadPaths: ['node_modules', 'packages'],
        importers: [
          {
            findFileUrl: (url) => {
              if (url.startsWith('~tgui-core/styles/')) {
                return pathToFileURL(
                  resolve(
                    dirname(
                      Bun.resolveSync('tgui-core/styles', import.meta.dir),
                    ),
                    url.slice('~tgui-core/styles/'.length),
                  ),
                );
              }
              if (url.startsWith('highlight.js/')) {
                return pathToFileURL(
                  Bun.resolveSync(url, resolve(import.meta.dir, '..')),
                );
              }
              return url.startsWith('~')
                ? pathToFileURL(Bun.resolveSync(url.slice(1), import.meta.dir))
                : null;
            },
          },
        ],
        logger: { warn() {}, debug() {} },
      })
    ).css;
    await Bun.write(
      '../data/material-engineering-preview.html',
      `<!doctype html><html><head><meta charset="utf-8"><style>${css}\nhtml,body{background:#14191e!important;margin:0;width:680px;height:1000px;}body{padding:20px;font-size:13px}.Window{position:relative!important;width:640px!important;height:auto!important;background:#252b31}.Window__content{position:relative!important;padding:10px!important;overflow:visible!important}</style></head><body>${view.container.innerHTML}</body></html>`,
    );
  }
});
