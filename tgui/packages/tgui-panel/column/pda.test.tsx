// The real PDA, docked: routes.tsx finds it the way the bundle does (require.context, here backed by the file system), it loads as the
// bundle's on-demand chunk would (lazy import), and it draws inside the column from its own window's messages.
import './requireContext.testing';
import { afterEach, describe, expect, it } from 'bun:test';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { cleanup, render, waitFor } from '@testing-library/react';

const { EmbeddedInterface } = await import('tgui/routes');
const { applyEmbeddedMessage, createEmbeddedBackend } = await import(
  'tgui/embedded'
);

afterEach(cleanup);

describe('the PDA in the column', () => {
  it('loads through the interface routes and draws its main menu from its own data', async () => {
    const sent: unknown[][] = [];
    const backend = createEmbeddedBackend('col-3', (type, payload) =>
      sent.push([type, payload]),
    );
    applyEmbeddedMessage(backend, 'update', {
      config: {
        interface: { name: 'Pda' },
        title: 'Personal Data Assistant',
        status: 2,
        user: { name: 'Nick Price', observer: 0 },
      },
      data: {
        owner: 'Nick Price',
        ownjob: 'Site Manager',
        idInserted: 1,
        idLink: 'Nick Price, Site Manager',
        useRetro: 0,
        touch_silent: 0,
        cartridge_name: '',
        stationTime: '14:07',
        app: {
          name: 'Main Menu',
          icon: 'home',
          template: 'pda_main_menu',
          has_back: 0,
          is_home: 1,
        },
        // pda_main_menu's own data: no cartridge, no programs, no notes.
        categories: [],
        apps: {},
        pai: 0,
        notifying: {},
      },
    });
    const view = render(<EmbeddedInterface backend={backend} />);
    await waitFor(
      () => expect(view.container.textContent).toContain('Nick Price'),
      { timeout: 5000 },
    );
    // Not the routing error window: the PDA itself, and its screen.
    expect(view.container.textContent).not.toContain('could not be found');
    expect(view.container.textContent).not.toContain('failed to load');
    expect(view.container.querySelector('.EmbeddedInterface')).toBeTruthy();
  });
});

describe('docked interfaces load their code in the column page', () => {
  const pub = join(import.meta.dir, '..', '..', '..', 'public');
  const manifest = join(pub, 'tgui-chunk-manifest.json');
  const bundle = join(pub, 'tgui-panel.bundle.js');
  const built = existsSync(manifest) && existsSync(bundle);

  it.skipIf(!built)(
    "the column page's runtime knows the PDA's chunk, by the same file the server publishes",
    () => {
      const chunks: Record<string, string[]> = JSON.parse(
        readFileSync(manifest, 'utf8'),
      );
      const files = chunks.Pda;
      expect(files?.length).toBeGreaterThan(0);
      const page = readFileSync(bundle, 'utf8');
      // A chunk file is <id>.<hash>.chunk.js; the page's runtime maps the id to the hash to fetch it.
      for (const file of files) {
        const [id, hash] = file.split('.');
        expect(page).toContain(hash);
        expect(page).toMatch(new RegExp(`\\b${id}\\b`));
        expect(existsSync(join(pub, file))).toBe(true);
      }
    },
  );
});
