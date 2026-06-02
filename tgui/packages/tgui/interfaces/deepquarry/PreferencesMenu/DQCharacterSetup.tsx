// DQAdd — Character Setup window. Three vertical regions in the left pane (toolbar /
// tabs / scrollable page); right pane is the character preview + cycle background.
//
// The preview renders as plain <img> tags from base64 PNGs the server flattens
// out of the mannequin (one per cardinal direction) and the background icon.
// No BYOND map control, no ByondUi, no icon-size race — CSS scales the source
// pixels with image-rendering: pixelated. See /datum/preferences/proc/update_character_previews
// in code/modules/client/preferences.dm.

import { useEffect, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack, Tabs } from 'tgui-core/components';
import { CategoryPage } from './CategoryPage';
import type { CharacterPreviewAssets, CharacterSetupData } from './types';

/// Renders the BG image at the back and stacks the four direction sprites
/// (SOUTH top, NORTH, EAST, WEST bottom) in the center column at 1/3 of the
/// container width. Image-rendering: pixelated keeps the 32-px source crisp
/// when CSS scales it up.
const PreviewPane = ({ assets }: { assets: CharacterPreviewAssets }) => {
  const directions: Array<keyof Pick<
    CharacterPreviewAssets,
    'south' | 'north' | 'east' | 'west'
  >> = ['south', 'north', 'east', 'west'];
  return (
    <Box
      style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <Box
        style={{
          position: 'relative',
          aspectRatio: '3 / 4',
          maxWidth: '100%',
          maxHeight: '100%',
          height: '100%',
          // Wider sprites (dogborgs) render at the same pixel scale as a
          // human, which means a 64x32 chassis overflows the 32-wide center
          // column. Clip at the preview pane edge so the bleed never reaches
          // the main prefs content next door.
          overflow: 'hidden',
        }}
      >
        {assets.bg && (
          // Tiled background (3 cols × 4 rows of the 32-px source icon),
          // matching the original BYOND screen_loc "1,1 to 3,4" fill_rect.
          // A stretched single tile was the previous look; this restores the
          // 12-tile grid the BG was designed for.
          <Box
            style={{
              position: 'absolute',
              inset: 0,
              backgroundImage: `url('data:image/png;base64,${assets.bg}')`,
              backgroundRepeat: 'repeat',
              backgroundSize: '33.33% 25%',
              imageRendering: 'pixelated',
            }}
          />
        )}
        <Box
          style={{
            position: 'absolute',
            top: 0,
            left: '33.33%',
            width: '33.33%',
            height: '100%',
            display: 'flex',
            flexDirection: 'column',
          }}
        >
          {directions.map((dir) => (
            <Box
              key={dir}
              style={{
                flex: 1,
                minHeight: 0,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                // Wider sprites (dogborgs) overflow horizontally rather than
                // shrink vertically — without this they'd render at half the
                // visual height of an organic mannequin.
                overflow: 'visible',
              }}
            >
              {assets[dir] && (
                <img
                  src={`data:image/png;base64,${assets[dir]}`}
                  alt=""
                  style={{
                    // Match the slot height; width auto preserves aspect ratio.
                    // For 32x32 humans this fills the square slot exactly. For
                    // wider sprites (64x32 dogborgs) the image overflows to the
                    // sides at the same pixel scale — matches the user's
                    // expectation of "same scale as a character".
                    height: '100%',
                    width: 'auto',
                    imageRendering: 'pixelated',
                  }}
                />
              )}
            </Box>
          ))}
        </Box>
      </Box>
    </Box>
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
  const previewAssets = data.character_preview_assets ?? {};
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
      width={1500}
      height={900}
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
          {/* LEFT: toolbar + tabs + active page. grow=3 (vs right grow=1)
              gives the editor ~75% of the window width. */}
          <Stack.Item grow={3} basis={0}>
            <Stack fill vertical>
              <Stack.Item>
                <Box
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '4px',
                    padding: '2px 0',
                  }}
                >
                  <Button icon="folder-open" onClick={() => act('load')}>
                    Load
                  </Button>
                  <Button icon="copy" onClick={() => act('copy')}>
                    Copy
                  </Button>
                  <Box style={{ flex: 1 }} />
                  <Button
                    icon="sliders"
                    onClick={() => act('game_prefs')}
                    tooltip="Switches to Game Options."
                  >
                    Game Options
                  </Button>
                </Box>
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
                <Section fill fitted scrollable={!pageIsFullHeight}>
                  {selectedPage && (
                    <Box p={0.5} style={{ height: pageIsFullHeight ? '100%' : 'auto' }}>
                      <CategoryPage
                        page={selectedPage}
                        staticData={data.dq_editor_static}
                        fillHeight={pageIsFullHeight}
                      />
                    </Box>
                  )}
                </Section>
              </Stack.Item>
            </Stack>
          </Stack.Item>
          {/* RIGHT: preview + cycle background. */}
          <Stack.Item grow={1} basis={0}>
            <Stack fill vertical>
              <Stack.Item grow>
                <Section fill fitted>
                  <PreviewPane assets={previewAssets} />
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
