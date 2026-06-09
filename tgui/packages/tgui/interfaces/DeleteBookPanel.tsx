// Admin Delete Book panel — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Book = {
  id: string;
  author: string;
  title: string;
  category: string;
};

type Data = {
  books: Book[];
  error: string;
  sort_by: string;
};

export const DeleteBookPanel = () => {
  const { data, act } = useBackend<Data>();
  const { books, error, sort_by } = data;
  if (error) {
    return (
      <Window width={520} height={260} title="Delete Book">
        <Window.Content>
          <Section title="Administrative Management">
            <Box color="bad" bold>
              {error}
            </Box>
          </Section>
        </Window.Content>
      </Window>
    );
  }
  return (
    <Window width={760} height={620} title="Delete Book">
      <Window.Content scrollable>
        <Section
          title={`Administrative Management — ${books.length} books`}
          buttons={
            <>
              <Button onClick={() => act('order_by_id')} icon="hashtag">
                Order by SS13BN
              </Button>{' '}
              <Box inline color="label">
                Sort by:
              </Box>{' '}
              <Button
                compact
                selected={sort_by === 'author'}
                onClick={() => act('sort', { by: 'author' })}
              >
                Author
              </Button>{' '}
              <Button
                compact
                selected={sort_by === 'title'}
                onClick={() => act('sort', { by: 'title' })}
              >
                Title
              </Button>{' '}
              <Button
                compact
                selected={sort_by === 'category'}
                onClick={() => act('sort', { by: 'category' })}
              >
                Category
              </Button>
            </>
          }
        >
          {books.length === 0 ? (
            <EmptyState>No books.</EmptyState>
          ) : (
            <Stack vertical>
              {books.map((b) => (
                <Stack.Item key={b.id}>
                  <Box bold>{b.title}</Box>
                  <Box ml={1} color="label">
                    {b.author} — {b.category}
                  </Box>
                  <Box ml={1}>
                    <Button
                      compact
                      color="bad"
                      onClick={() => act('delete', { id: b.id })}
                    >
                      Delete
                    </Button>
                  </Box>
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
