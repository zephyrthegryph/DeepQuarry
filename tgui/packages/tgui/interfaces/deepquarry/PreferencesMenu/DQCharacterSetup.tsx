// DQAdd — Character Setup window. Three vertical regions in the left pane (toolbar /
// tabs / scrollable page); right pane is the character preview + cycle background.
//
// The preview renders as plain <img> tags from base64 PNGs the server flattens
// out of the mannequin (one per cardinal direction) and the background icon.
// No BYOND map control, no ByondUi, no icon-size race — CSS scales the source
// pixels with image-rendering: pixelated. See /datum/preferences/proc/update_character_previews
// in code/modules/client/preferences.dm.

import { useEffect, useMemo, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack, Tabs } from 'tgui-core/components';
import { CategoryPage } from './CategoryPage';
import { labelForCategory } from './labels';
import {
  buildSearchIndex,
  type SearchHit,
  SearchHighlightContext,
  SettingsSearch,
} from './search';
import type {
  CharacterPreviewAssets,
  CharacterSetupData,
  PrefCategory,
} from './types';

let catalogOwner = '';
let cachedStructureVersion = 0;
const categoryCache: Record<string, PrefCategory> = {};
const editorStaticCache: Record<string, Record<string, unknown>> = {};
const editorStaticVersions: Record<string, number | string> = {};
const editorDataCache: Record<string, Record<string, unknown>> = {};
/// Widget values and preview frames persist across updates: the server sends values for
/// the categories it is answering for, and the preview only when it changed.
const valuesCache: Record<string, unknown> = {};
let previewCache: CharacterPreviewAssets = {};
/// The owner (prefs + slot) whose every-tab prefetch has been requested.
let prefetchedOwner = '';

const clearRecord = (record: Record<string, unknown>) => {
  for (const key of Object.keys(record)) delete record[key];
};

/// Renders the BG image at the back and stacks the four direction sprites
/// (SOUTH top, NORTH, EAST, WEST bottom) in the center column at 1/3 of the
/// container width. Image-rendering: pixelated keeps the 32-px source crisp
/// when CSS scales it up.
const PreviewPane = ({ assets }: { assets: CharacterPreviewAssets }) => {
  const directions: Array<
    keyof Pick<CharacterPreviewAssets, 'south' | 'north' | 'east' | 'west'>
  > = ['south', 'north', 'east', 'west'];
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

// Editors that fill their container and manage their own internal scrolling. When the
// active page hosts one of these, the wrapping Section drops `scrollable` so we don't
// get a redundant outer scrollbar on top of the editor's own (and the editor gets to
// use the full available height instead of a measured-content height).
const FULL_HEIGHT_EDITORS = new Set<string>([
  'loadout',
  'mind_body',
  'faction_affiliations',
]);

export const DQCharacterSetup = () => {
  const { act, data } = useBackend<CharacterSetupData>();
  const owner = data.dq_cache_key ?? 'legacy';
  if (catalogOwner !== owner) {
    catalogOwner = owner;
    cachedStructureVersion = 0;
    clearRecord(categoryCache);
    clearRecord(editorStaticCache);
    clearRecord(editorStaticVersions);
    clearRecord(editorDataCache);
    clearRecord(valuesCache);
  }
  const structureVersion = data.dq_structure_version ?? 1;
  if (cachedStructureVersion !== structureVersion) {
    cachedStructureVersion = structureVersion;
    clearRecord(categoryCache);
  }
  for (const category of data.dq_categories ?? []) {
    categoryCache[category.category] = category;
  }
  Object.assign(categoryCache, data.dq_category_patch ?? {});
  const staticPatch =
    data.dq_editor_static_patch ?? data.dq_editor_static ?? {};
  Object.assign(editorStaticCache, staticPatch);
  for (const key of Object.keys(staticPatch)) {
    editorStaticVersions[key] = data.dq_editor_versions?.[key] ?? 1;
  }
  Object.assign(editorDataCache, data.dq_editor_data ?? {});
  Object.assign(valuesCache, data.dq_values ?? {});
  if (data.character_preview_assets) {
    previewCache = data.character_preview_assets;
  }

  const categoryIndex = data.dq_category_index ?? Object.keys(categoryCache);
  const values = valuesCache;
  const previewAssets = previewCache;
  const [selected, setSelected] = useState<string | null>(null);
  const moreCategories = (data.dq_more_categories ?? []).filter((c) =>
    categoryIndex.includes(c),
  );
  const mainCategories = categoryIndex.filter(
    (c) => !moreCategories.includes(c),
  );
  const [highlight, setHighlight] = useState<string | null>(null);
  const [pendingAnchor, setPendingAnchor] = useState<string | null>(null);
  // Rebuilt when a category structure arrives (the prefetch fills every tab).
  const searchKey = `${categoryIndex.join('|')}#${Object.keys(categoryCache).length}#${structureVersion}`;
  const searchHits = useMemo(
    () => buildSearchIndex(categoryIndex, categoryCache),
    [searchKey],
  );
  const selectCategory = (category: string) => {
    setSelected(category);
    act('dq_select_category', {
      category,
      force_catalogs: !categoryCache[category],
    });
  };
  const jumpTo = (hit: SearchHit) => {
    if (hit.category !== selected) selectCategory(hit.category);
    setPendingAnchor(hit.anchor || null);
    setHighlight(hit.anchor || null);
  };
  // After a jump, wait for the page to render the anchor, then scroll it into view.
  useEffect(() => {
    if (!pendingAnchor) return;
    let tries = 0;
    const timer = setInterval(() => {
      const el = document.querySelector(
        `[data-dq-anchor="${CSS.escape(pendingAnchor)}"]`,
      );
      tries++;
      if (el) {
        el.scrollIntoView({ block: 'center' });
        setPendingAnchor(null);
        clearInterval(timer);
      } else if (tries > 40) {
        setPendingAnchor(null);
        clearInterval(timer);
      }
    }, 50);
    return () => clearInterval(timer);
  }, [pendingAnchor]);
  useEffect(() => {
    if (!highlight) return;
    const timer = setTimeout(() => setHighlight(null), 2500);
    return () => clearTimeout(timer);
  }, [highlight]);

  // Land on the first available category once data arrives. Without this, the initial
  // poll with empty `categories` locks `selected = null` and the tab strip renders
  // unhighlighted until the user clicks something.
  useEffect(() => {
    if (!selected && categoryIndex.length > 0) {
      setSelected(data.dq_active_category ?? categoryIndex[0]);
    } else if (selected && !categoryIndex.includes(selected)) {
      setSelected(data.dq_active_category ?? categoryIndex[0] ?? null);
    }
  }, [categoryIndex, data.dq_active_category, selected]);

  const selectedPage = selected ? categoryCache[selected] : undefined;
  const activeEditorVersions =
    selected === data.dq_active_category ? (data.dq_editor_versions ?? {}) : {};
  const missingEditorCatalog =
    !!selectedPage &&
    selectedPage.groups.some((group) =>
      group.items.some(
        (item) =>
          item.type === 'editor' &&
          activeEditorVersions[item.key] !== undefined &&
          editorStaticVersions[item.key] !== activeEditorVersions[item.key],
      ),
    );

  useEffect(() => {
    if (!selected || selected !== data.dq_active_category) return;
    if (!selectedPage || missingEditorCatalog) {
      act('dq_select_category', {
        category: selected,
        force_catalogs: true,
      });
    }
  }, [
    act,
    data.dq_active_category,
    missingEditorCatalog,
    selected,
    selectedPage,
  ]);

  // Once the first page has its catalogs, ask for every other tab in the background so
  // later switches render from this cache at once (the server's answer then only
  // refreshes values).
  useEffect(() => {
    if (prefetchedOwner === owner || !selectedPage || missingEditorCatalog) {
      return;
    }
    const timer = setTimeout(() => {
      prefetchedOwner = owner;
      act('dq_prefetch_categories');
    }, 300);
    return () => clearTimeout(timer);
  }, [act, owner, selectedPage, missingEditorCatalog]);

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
                    gap: '0.333em',
                    padding: '0.167em 0',
                  }}
                >
                  <Button icon="folder-open" onClick={() => act('load')}>
                    Load
                  </Button>
                  <Button icon="copy" onClick={() => act('copy')}>
                    Copy
                  </Button>
                  <SettingsSearch hits={searchHits} onPick={jumpTo} />
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
                  {mainCategories.map((category) => (
                    <Tabs.Tab
                      key={category}
                      selected={category === selected}
                      onClick={() => selectCategory(category)}
                    >
                      {labelForCategory(category)}
                    </Tabs.Tab>
                  ))}
                  {moreCategories.length > 0 && (
                    <Tabs.Tab
                      key="__more"
                      icon="ellipsis"
                      selected={!!selected && moreCategories.includes(selected)}
                      onClick={() => {
                        if (!selected || !moreCategories.includes(selected)) {
                          selectCategory(moreCategories[0]);
                        }
                      }}
                    >
                      More
                    </Tabs.Tab>
                  )}
                </Tabs>
              </Stack.Item>
              {!!selected && moreCategories.includes(selected) && (
                <Stack.Item>
                  <Tabs>
                    {moreCategories.map((category) => (
                      <Tabs.Tab
                        key={category}
                        selected={category === selected}
                        onClick={() => selectCategory(category)}
                      >
                        {labelForCategory(category)}
                      </Tabs.Tab>
                    ))}
                  </Tabs>
                </Stack.Item>
              )}
              <Stack.Item grow>
                <Section fill fitted scrollable={!pageIsFullHeight}>
                  {selectedPage ? (
                    <Box
                      p={0.5}
                      style={{ height: pageIsFullHeight ? '100%' : 'auto' }}
                    >
                      <SearchHighlightContext.Provider value={highlight}>
                        <CategoryPage
                          page={selectedPage}
                          staticData={editorStaticCache}
                          values={values}
                          editorData={editorDataCache}
                          fillHeight={pageIsFullHeight}
                        />
                      </SearchHighlightContext.Provider>
                    </Box>
                  ) : (
                    <Box p={2} color="label">
                      Loading category...
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
