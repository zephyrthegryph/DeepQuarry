// DQAdd — Character Setup window. Three vertical regions in the left pane (toolbar /
// tabs / scrollable page); right pane is the character preview + cycle background.
//
// The preview renders as plain <img> tags from base64 PNGs the server flattens
// out of the mannequin (one per cardinal direction) and the background icon.
// No BYOND map control, no ByondUi, no icon-size race — CSS scales the source
// pixels with image-rendering: pixelated. See /datum/preferences/proc/update_character_previews
// in code/modules/client/preferences.dm.

import { useEffect, useRef, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack, Tabs } from 'tgui-core/components';
import { createLogger } from '../../../logging';
import { CategoryPage } from './CategoryPage';
import {
  ColorToolsContext,
  colorsInUse,
  type SlotName,
  slotColors,
} from './colors';
import type { EditorDataCache, EditorStaticCache } from './editors';
import { labelForCategory } from './labels';
import type {
  CharacterPreviewAssets,
  CharacterSetupData,
  PrefCategory,
} from './types';

const logger = createLogger('prefs');

let catalogOwner = '';
let cachedStructureVersion = 0;
const categoryCache: Record<string, PrefCategory> = {};
/// Tabs whose cached page predates the latest structure version: shown, but asked for again.
const staleCategories = new Set<string>();
const editorStaticCache: EditorStaticCache = {};
const editorStaticVersions: Record<string, number | string> = {};
const editorDataCache: EditorDataCache = {};
/// Widget values and preview frames persist across updates: the server sends values for
/// the categories it is answering for, and the preview only when it changed.
const valuesCache: Record<string, unknown> = {};
const colorLinksCache: Record<string, string> = {};
let previewCache: CharacterPreviewAssets = {};
/// The tabs whose prefetch has been requested ("owner|structure version|tab"): one tab per request, so no answer is huge.
const prefetchRequested = new Set<string>();

/// The entries of a per-editor payload that the server answered (not null).
const answered = <T extends object>(payload: T | null | undefined) =>
  Object.fromEntries(
    Object.entries(payload ?? {}).filter(([, value]) => value != null),
  ) as { [K in keyof T]?: NonNullable<T[K]> };

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
                alignItems: 'flex-end',
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
                  onLoad={(e) => {
                    // The server bakes the body size into the sprite; keep it. A slot holds the largest body
                    // (PREVIEW_MAX_SCALE x 32 px tall), so a normal body is that fraction of it and a bigger one fills more.
                    const img = e.currentTarget;
                    img.style.height = `${(100 * img.naturalHeight) / (32 * PREVIEW_MAX_SCALE)}%`;
                  }}
                  style={{
                    height: `${100 / PREVIEW_MAX_SCALE}%`,
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

/// The largest body size (RESIZE_HUGE): a slot is tall enough for it, so every size shows at its true scale.
const PREVIEW_MAX_SCALE = 2;

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
    staleCategories.clear();
    clearRecord(editorStaticCache);
    clearRecord(editorStaticVersions);
    clearRecord(editorDataCache);
    clearRecord(valuesCache);
    clearRecord(colorLinksCache);
    prefetchRequested.clear();
  }
  const structureVersion = data.dq_structure_version ?? 1;
  if (cachedStructureVersion !== structureVersion) {
    // A new structure (a species or taur change rebuilt the pages) arrives as patches for the tabs it touched. The
    // pages already held stay on screen and are replaced in place, so a change never blanks the tab being edited;
    // a tab not patched yet is asked for again when it is opened.
    cachedStructureVersion = structureVersion;
    for (const key of Object.keys(categoryCache)) staleCategories.add(key);
    prefetchRequested.clear();
  }
  for (const category of data.dq_categories ?? []) {
    categoryCache[category.category] = category;
    staleCategories.delete(category.category);
  }
  for (const [key, page] of Object.entries(data.dq_category_patch ?? {})) {
    categoryCache[key] = page;
    staleCategories.delete(key);
  }
  // The server sends null for an editor it did not answer for: the window keeps what it has.
  const staticPatch = answered(data.dq_editor_static_patch);
  Object.assign(editorStaticCache, staticPatch);
  for (const key of Object.keys(staticPatch)) {
    editorStaticVersions[key] = data.dq_editor_versions?.[key] ?? 1;
  }
  Object.assign(editorDataCache, answered(data.dq_editor_data));
  Object.assign(valuesCache, data.dq_values ?? {});
  Object.assign(colorLinksCache, data.dq_color_links ?? {});
  if (data.character_preview_assets) {
    previewCache = data.character_preview_assets;
  }

  const categoryIndex = data.dq_category_index ?? Object.keys(categoryCache);
  const values = valuesCache;
  const previewAssets = previewCache;
  const [selected, setSelected] = useState<string | null>(null);
  const [brush, setBrush] = useState<SlotName | null>(null);
  const colorTools = {
    slots: slotColors(values),
    links: colorLinksCache,
    inUse: colorsInUse(values),
    brush,
    setBrush,
  };
  const requestedAt = useRef<Record<string, number>>({});
  const selectCategory = (category: string) => {
    setSelected(category);
    requestedAt.current[category] = performance.now();
    act('dq_select_category', {
      category,
      force_catalogs: !categoryCache[category] || staleCategories.has(category),
    });
  };

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

  // How long a tab took from the click to its page (the log is where "the Loadout tab is slow" gets measured).
  useEffect(() => {
    if (!selected || !selectedPage) return;
    const asked = requestedAt.current[selected];
    if (asked === undefined) return;
    delete requestedAt.current[selected];
    logger.log(
      `tab ${selected} ready in ${Math.round(performance.now() - asked)} ms (${missingEditorCatalog ? 'catalogs still pending' : 'complete'})`,
    );
  }, [selected, selectedPage, missingEditorCatalog]);

  // A tab with no page after a while is asked for again (and the wait logged), so a lost answer cannot leave it on
  // "Loading category..." for good.
  useEffect(() => {
    if (!selected || selectedPage) return;
    let tries = 0;
    const timer = setInterval(() => {
      tries++;
      logger.warn(
        `tab ${selected} still has no page after ${tries * 2} s; asking again (server active tab ${data.dq_active_category ?? 'none'})`,
      );
      requestedAt.current[selected] ??= performance.now();
      act('dq_select_category', { category: selected, force_catalogs: true });
      if (tries >= 10) clearInterval(timer);
    }, 2000);
    return () => clearInterval(timer);
  }, [act, selected, selectedPage, data.dq_active_category]);

  // Once the first page has its catalogs, ask for every other tab in the background, one at a time (the next after
  // the last one's page has arrived), so later switches render from this cache at once and no answer is huge.
  const [prefetching, setPrefetching] = useState<string | null>(null);
  useEffect(() => {
    if (!prefetching) return;
    if (categoryCache[prefetching] && !staleCategories.has(prefetching)) {
      setPrefetching(null);
      return;
    }
    const timer = setTimeout(() => setPrefetching(null), 3000);
    return () => clearTimeout(timer);
  }, [
    prefetching,
    selectedPage,
    data.dq_structure_version,
    data.dq_category_patch,
  ]);
  useEffect(() => {
    if (prefetching || !selectedPage || missingEditorCatalog) return;
    const next = categoryIndex.find(
      (c) =>
        c !== selected &&
        (!categoryCache[c] || staleCategories.has(c)) &&
        !prefetchRequested.has(`${owner}|${structureVersion}|${c}`),
    );
    if (!next) return;
    const timer = setTimeout(() => {
      prefetchRequested.add(`${owner}|${structureVersion}|${next}`);
      act('dq_prefetch_categories', { category: next });
      setPrefetching(next);
    }, 250);
    return () => clearTimeout(timer);
  }, [
    act,
    owner,
    structureVersion,
    selected,
    selectedPage,
    missingEditorCatalog,
    prefetching,
    categoryIndex,
  ]);

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
                  {categoryIndex.map((category) => (
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
              <Stack.Item grow>
                <Section fill fitted scrollable={!pageIsFullHeight}>
                  {selectedPage ? (
                    <Box
                      p={0.5}
                      style={{ height: pageIsFullHeight ? '100%' : 'auto' }}
                    >
                      <ColorToolsContext.Provider value={colorTools}>
                        <CategoryPage
                          page={selectedPage}
                          staticData={editorStaticCache}
                          values={values}
                          editorData={editorDataCache}
                          fillHeight={pageIsFullHeight}
                        />
                      </ColorToolsContext.Provider>
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
