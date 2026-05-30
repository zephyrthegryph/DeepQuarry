// Cataloguer — structured TGUI.
//
// Two views in one window: the category-grouped index, and a per-item
// detail view. DM side chooses by setting `detail` (a typed object) or
// leaving it null.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type CatalogueItem = {
  name: string;
  ref: string;
  visible: BooleanLike;
};

type Group = {
  name: string;
  items: CatalogueItem[];
};

type Detail = {
  name: string;
  desc: string;
  value: number;
  cataloguers: string | null;
  visible: BooleanLike;
  ref: string;
};

type Data = {
  points_stored: number;
  debug: BooleanLike;
  detail: Detail | null;
  groups?: Group[];
};

export const Cataloguer = () => {
  const { data, act } = useBackend<Data>();
  const { points_stored, debug, detail, groups } = data;
  return (
    <Window width={520} height={620} title="Cataloguer">
      <Window.Content scrollable>
        <Section
          title={`Exploration Points: ${points_stored}`}
          buttons={
            <>
              <Button icon="bullseye" onClick={() => act('pulse_scan')}>
                Highlight Scannables
              </Button>{' '}
              <Button icon="rotate" onClick={() => act('refresh')}>
                Refresh
              </Button>
            </>
          }
        />
        {detail ? (
          <Section
            title={detail.name.toUpperCase()}
            buttons={
              <Button icon="arrow-left" onClick={() => act('back_to_list')}>
                Back to List
              </Button>
            }
          >
            {debug && !detail.visible ? (
              <Box mb={1}>
                <Button
                  color="bad"
                  icon="unlock"
                  onClick={() => act('debug_unlock', { ref: detail.ref })}
                >
                  (DEBUG) Force Discovery
                </Button>
              </Box>
            ) : null}
            <Box italic mb={1}>
              {detail.desc}
            </Box>
            <Box mb="2px">
              Cataloguers:{' '}
              {detail.cataloguers ? (
                <b>{detail.cataloguers}</b>
              ) : (
                <Box inline color="label">
                  Catalogued by nobody.
                </Box>
              )}
            </Box>
            <Box>
              Worth <b>{detail.value}</b> exploration points.
            </Box>
          </Section>
        ) : (
          (groups ?? []).map((g) => (
            <Section key={g.name} title={g.name}>
              {g.items.length === 0 ? (
                <EmptyState>No items here.</EmptyState>
              ) : (
                <Stack wrap>
                  {g.items.map((it) => (
                    <Stack.Item key={it.ref}>
                      <Button onClick={() => act('show_data', { ref: it.ref })}>
                        {it.name}
                      </Button>
                    </Stack.Item>
                  ))}
                </Stack>
              )}
            </Section>
          ))
        )}
      </Window.Content>
    </Window>
  );
};
