// Library visitor computer — TGUI.
//
// Set search filters then run a search against the books DB. Results
// table shown until "Back" returns to the filter view.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Result = {
  author: string;
  title: string;
  category: string;
  id: string;
};

type Data = {
  screenstate: number;
  title: string;
  category: string;
  author: string;
  has_db: BooleanLike;
  has_query: BooleanLike;
  results: Result[];
};

export const LibraryVisitor = () => {
  const { data, act } = useBackend<Data>();
  const { screenstate, title, category, author, has_db, has_query, results } =
    data;

  if (screenstate === 1) {
    return (
      <Window width={620} height={480} title="Library Visitor">
        <Window.Content scrollable>
          <Section
            title="Search Results"
            buttons={
              <Button icon="arrow-left" onClick={() => act('back')}>
                Back
              </Button>
            }
          >
            {!has_db ? (
              <Box color="bad" bold>
                ERROR: Unable to contact External Archive. Please contact your
                system administrator for assistance.
              </Box>
            ) : !has_query ? (
              <Box color="bad" bold>
                ERROR: Malformed search request. Please contact your system
                administrator for assistance.
              </Box>
            ) : (
              <Table>
                <Table.Row header>
                  <Table.Cell>AUTHOR</Table.Cell>
                  <Table.Cell>TITLE</Table.Cell>
                  <Table.Cell>CATEGORY</Table.Cell>
                  <Table.Cell>
                    SS<sup>13</sup>BN
                  </Table.Cell>
                </Table.Row>
                {results.map((r) => (
                  <Table.Row key={r.id}>
                    <Table.Cell>{r.author}</Table.Cell>
                    <Table.Cell>{r.title}</Table.Cell>
                    <Table.Cell>{r.category}</Table.Cell>
                    <Table.Cell>{r.id}</Table.Cell>
                  </Table.Row>
                ))}
              </Table>
            )}
          </Section>
        </Window.Content>
      </Window>
    );
  }

  return (
    <Window width={420} height={260} title="Library Visitor">
      <Window.Content>
        <Section title="Search Settings">
          <LabeledList>
            <LabeledList.Item label="Title">
              <Button onClick={() => act('settitle')}>{title || '—'}</Button>
            </LabeledList.Item>
            <LabeledList.Item label="Category">
              <Button onClick={() => act('setcategory')}>{category}</Button>
            </LabeledList.Item>
            <LabeledList.Item label="Author">
              <Button onClick={() => act('setauthor')}>{author || '—'}</Button>
            </LabeledList.Item>
          </LabeledList>
          <Box mt={2}>
            <Button
              fluid
              icon="search"
              color="good"
              onClick={() => act('search')}
            >
              Start Search
            </Button>
          </Box>
        </Section>
      </Window.Content>
    </Window>
  );
};
