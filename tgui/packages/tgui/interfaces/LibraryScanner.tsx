// Library scanner — TGUI.
//
// Holds a book in its contents and a cached datum reference. Scan
// stores the loaded book into the cache. Clear/Eject remove the
// cache or the book.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Data = {
  has_cache: BooleanLike;
  cache_name: string;
  has_book: BooleanLike;
};

export const LibraryScanner = () => {
  const { data, act } = useBackend<Data>();
  const { has_cache, cache_name, has_book } = data;

  return (
    <Window width={420} height={220} title="Scanner Control Interface">
      <Window.Content>
        <Section>
          <Box mb={1}>
            {has_cache ? (
              <Box color="label">
                Data stored in memory:{' '}
                <Box inline bold>
                  {cache_name}
                </Box>
              </Box>
            ) : (
              <EmptyState>No data stored in memory.</EmptyState>
            )}
          </Box>
          <Button icon="search" onClick={() => act('scan')}>
            Scan
          </Button>{' '}
          {has_cache ? (
            <Button icon="eraser" color="bad" onClick={() => act('clear')}>
              Clear Memory
            </Button>
          ) : null}{' '}
          {has_book ? (
            <Button icon="eject" onClick={() => act('eject')}>
              Remove Book
            </Button>
          ) : null}
        </Section>
      </Window.Content>
    </Window>
  );
};
