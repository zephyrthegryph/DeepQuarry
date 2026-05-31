// DQAdd — Character Setup window. Three vertical regions in the left pane (toolbar /
// tabs / scrollable page); right pane is the preview map + cycle background.

import { useEffect, useRef, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  ByondUi,
  Section,
  Stack,
  Tabs,
} from 'tgui-core/components';
import { CategoryPage } from './CategoryPage';
import type { CharacterSetupData } from './types';

/// Wraps ByondUi for the character preview map.
///
/// The element `character_preview_map` is pre-declared in interface/skin.dmf with
/// `icon-size = 64` and a baseline size of 240x520, so the moment ByondUi flips it
/// to visible the per-tile resolution is already correct. Passing `view = 3x8` at
/// mount time crops the map to the area the preview screen objects span (BG covers
/// 1,1 to 3,8; PMH sits at 2,7 — see code/modules/client/preferences.dm). Without
/// that, BYOND showed tile (0,0) of an unfocused world surrounded by emptiness.
///
/// Container is fixed at 240x520px and centered: this matches the skin's reserved
/// size exactly so BYOND doesn't have to rescale, and 240 across × 520 down lines up
/// at 64 px per tile × 3 wide / 8 tall (192x512 — fits with a couple px of breathing
/// room). On a narrow window the surrounding flex container scrolls instead of
/// trying to fit a smaller preview into too little space.
///
/// The ResizeObserver is still here so ByondUi re-measures if the WHOLE window
/// resizes; the BYOND embed listens to global resize events specifically.
const PREVIEW_WIDTH = 240;
const PREVIEW_HEIGHT = 520;

const PreviewMap = () => {
  const containerRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const el = containerRef.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(() => {
      window.dispatchEvent(new Event('resize'));
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);
  return (
    <div
      ref={containerRef}
      style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        overflow: 'auto',
      }}
    >
      <ByondUi
        params={{
          id: 'character_preview_map',
          type: 'map',
          view: '3x8',
          'icon-size': '64',
        }}
        style={{
          width: `${PREVIEW_WIDTH}px`,
          height: `${PREVIEW_HEIGHT}px`,
        }}
      />
    </div>
  );
};

// Consolidated, shorter labels so all tabs fit on one row at the default window width.
// Keys match /datum/preference.category values written by tag_pref(). Categories without
// an override here fall back to titleCase(category).
const CATEGORY_LABELS: Record<string, string> = {
  identity: 'Identity',
  appearance: 'Looks',
  // Renamed from "Body" so the new Mind & Body specialty tab can own that word; the
  // size_voice category is really size sliders + voice prefs, "Size" is closer anyway.
  size_voice: 'Size',
  loadout: 'Loadout',
  occupation: 'Jobs',
  traits: 'Traits',
  mind_body: 'Mind & Body',
  antag: 'Antag',
  vore: 'Vore',
  game: 'Game',
  misc: 'Misc',
};

const titleCase = (s: string) =>
  s.replace(/(^|[_\s])([a-z])/g, (_, sep, ch) => (sep ? ' ' : '') + ch.toUpperCase());

const labelForCategory = (key: string) => CATEGORY_LABELS[key] ?? titleCase(key);

// Editors that fill their container and manage their own internal scrolling. When the
// active page hosts one of these, the wrapping Section drops `scrollable` so we don't
// get a redundant outer scrollbar on top of the editor's own (and the editor gets to
// use the full available height instead of a measured-content height).
const FULL_HEIGHT_EDITORS = new Set<string>(['loadout', 'mind_body']);

export const DQCharacterSetup = () => {
  const { act, data } = useBackend<CharacterSetupData>();
  const categories = data.dq_categories ?? [];
  const [selected, setSelected] = useState<string | null>(null);

  // Land on the first available category once data arrives. Without this, the initial
  // poll with empty `categories` locks `selected = null` and the tab strip renders
  // unhighlighted until the user clicks something.
  useEffect(() => {
    if (!selected && categories.length > 0) {
      setSelected(categories[0].category);
    }
  }, [categories, selected]);

  const selectedPage =
    categories.find((p) => p.category === selected) ?? categories[0];

  const pageIsFullHeight =
    selectedPage?.groups.some((g) =>
      g.items.some(
        (i) => i.type === 'editor' && FULL_HEIGHT_EDITORS.has(i.key),
      ),
    ) ?? false;

  return (
    <Window
      width={1100}
      height={760}
      buttons={
        <Button
          icon="expand"
          color="transparent"
          tooltip="Maximize"
          onClick={async () => {
            Byond.winset(Byond.windowId, {
              'is-maximized': !(await Byond.winget(
                Byond.windowId,
                'is-maximized',
              )),
            });
          }}
        />
      }
    >
      <Window.Content>
        <Stack fill>
          {/* LEFT: toolbar + tabs + active page */}
          <Stack.Item grow={2} basis={0}>
            <Stack fill vertical>
              <Stack.Item>
                <Section>
                  <Stack align="center">
                    <Stack.Item>
                      <Button icon="folder-open" onClick={() => act('load')}>
                        Load
                      </Button>
                    </Stack.Item>
                    <Stack.Item>
                      <Button icon="copy" onClick={() => act('copy')}>
                        Copy
                      </Button>
                    </Stack.Item>
                    <Stack.Item grow>
                      <Box />
                    </Stack.Item>
                    <Stack.Item>
                      <Button
                        icon="sliders"
                        onClick={() => act('game_prefs')}
                        tooltip="Switches to Game Options."
                      >
                        Game Options
                      </Button>
                    </Stack.Item>
                  </Stack>
                </Section>
              </Stack.Item>
              <Stack.Item>
                <Tabs fluid>
                  {categories.map((page) => (
                    <Tabs.Tab
                      key={page.category}
                      selected={page.category === selected}
                      onClick={() => setSelected(page.category)}
                    >
                      {labelForCategory(page.category)}
                    </Tabs.Tab>
                  ))}
                </Tabs>
              </Stack.Item>
              <Stack.Item grow>
                <Section fill scrollable={!pageIsFullHeight}>
                  {selectedPage && (
                    <CategoryPage
                      page={selectedPage}
                      staticData={data.dq_editor_static}
                      fillHeight={pageIsFullHeight}
                    />
                  )}
                </Section>
              </Stack.Item>
            </Stack>
          </Stack.Item>
          {/* RIGHT: preview map + cycle background. */}
          <Stack.Item grow={1} basis={0}>
            <Stack fill vertical>
              <Stack.Item grow>
                <Section fill>
                  <PreviewMap />
                </Section>
              </Stack.Item>
              <Stack.Item>
                <Button
                  fluid
                  icon="arrows-rotate"
                  onClick={() => act('cycle_background')}
                >
                  Cycle Background
                </Button>
              </Stack.Item>
            </Stack>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
