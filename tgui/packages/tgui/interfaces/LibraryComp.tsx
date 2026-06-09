import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type InventoryBook = {
  ref: string;
  name: string;
};

type Checkout = {
  ref: string;
  bookname: string;
  mobname: string;
  taken_min: number;
  due_min: number;
  overdue: BooleanLike;
};

type InternalBook = {
  path: string;
  name: string;
  author: string;
  category: string;
};

type ExternalBook = {
  id: string;
  author: string;
  title: string;
  category: string;
};

type ScannerCache = {
  name: string;
  author: string;
};

type Data = {
  screenstate: number;
  emagged: BooleanLike;
  is_admin: BooleanLike;
  buffer_book: string;
  buffer_mob: string;
  checkout_period: number;
  world_time_min: number;
  sort_by: string;
  has_scanner: BooleanLike;
  scanner_cache: ScannerCache | null;
  upload_category: string;
  has_db: BooleanLike;
  inventory: InventoryBook[];
  checkouts: Checkout[];
  internal_archive: InternalBook[];
  external_archive: ExternalBook[];
};

const ScreenLabel: Record<number, string> = {
  0: 'Main Menu',
  1: 'General Inventory',
  2: 'Checked Out Inventory',
  3: 'Check Out a Book',
  4: 'Internal Archive',
  5: 'Upload New Title',
  7: 'Forbidden Lore Vault',
  8: 'External Archive',
};

export const LibraryComp = () => {
  const { data } = useBackend<Data>();
  return (
    <Window
      width={620}
      height={620}
      title={`Book Inventory Management — ${ScreenLabel[data.screenstate] ?? ''}`}
    >
      <Window.Content scrollable>
        <Screen />
      </Window.Content>
    </Window>
  );
};

const BackToMain = () => {
  const { act } = useBackend<Data>();
  return (
    <Box mt={2}>
      <Button
        icon="arrow-left"
        onClick={() => act('switchscreen', { screen: 0 })}
      >
        Return to main menu
      </Button>
    </Box>
  );
};

const Screen = () => {
  const { data } = useBackend<Data>();
  switch (data.screenstate) {
    case 0:
      return <MainMenu />;
    case 1:
      return <Inventory />;
    case 2:
      return <CheckedOut />;
    case 3:
      return <CheckoutForm />;
    case 4:
      return <InternalArchive />;
    case 5:
      return <Upload />;
    case 7:
      return <ForbiddenVault />;
    case 8:
      return <ExternalArchive />;
    default:
      return (
        <Section>
          <Box color="bad">Unknown screen {data.screenstate}.</Box>
          <BackToMain />
        </Section>
      );
  }
};

const MainMenu = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Section title="Main Menu">
      <Stack vertical>
        <Stack.Item>
          <Button fluid onClick={() => act('switchscreen', { screen: 1 })}>
            1. View General Inventory
          </Button>
        </Stack.Item>
        <Stack.Item>
          <Button fluid onClick={() => act('switchscreen', { screen: 2 })}>
            2. View Checked Out Inventory
          </Button>
        </Stack.Item>
        <Stack.Item>
          <Button fluid onClick={() => act('switchscreen', { screen: 3 })}>
            3. Check out a Book
          </Button>
        </Stack.Item>
        <Stack.Item>
          <Button fluid onClick={() => act('switchscreen', { screen: 4 })}>
            4. Connect to Internal Archive
          </Button>
        </Stack.Item>
        <Stack.Item>
          <Button fluid onClick={() => act('switchscreen', { screen: 5 })}>
            5. Upload New Title to Archive
          </Button>
        </Stack.Item>
        <Stack.Item>
          <Button fluid onClick={() => act('print_bible')}>
            6. Print a Bible
          </Button>
        </Stack.Item>
        <Stack.Item>
          <Button fluid onClick={() => act('switchscreen', { screen: 8 })}>
            8. Access External Archive
          </Button>
        </Stack.Item>
        {data.emagged ? (
          <Stack.Item>
            <Button
              fluid
              color="bad"
              onClick={() => act('switchscreen', { screen: 7 })}
            >
              7. Access the Forbidden Lore Vault
            </Button>
          </Stack.Item>
        ) : null}
      </Stack>
    </Section>
  );
};

const Inventory = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Section title="Inventory">
      {data.inventory.length === 0 ? (
        <EmptyState>No books in inventory.</EmptyState>
      ) : (
        <Stack vertical>
          {data.inventory.map((b) => (
            <Stack.Item key={b.ref}>
              <Button
                color="bad"
                onClick={() => act('delbook', { ref: b.ref })}
              >
                Delete
              </Button>{' '}
              {b.name}
            </Stack.Item>
          ))}
        </Stack>
      )}
      <BackToMain />
    </Section>
  );
};

const CheckedOut = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Section title="Checked Out Books">
      {data.checkouts.length === 0 ? (
        <EmptyState>No books currently checked out.</EmptyState>
      ) : (
        <Stack vertical>
          {data.checkouts.map((b) => (
            <Stack.Item key={b.ref}>
              <Box bold>"{b.bookname}"</Box>
              <Box>Checked out to: {b.mobname}</Box>
              <Box color="label">
                Taken: {b.taken_min} min ago, Due: in{' '}
                {b.overdue ? (
                  <Box inline color="bad" bold>
                    OVERDUE ({b.due_min})
                  </Box>
                ) : (
                  <Box inline>{b.due_min} min</Box>
                )}
              </Box>
              <Button onClick={() => act('checkin', { ref: b.ref })}>
                Check In
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      )}
      <BackToMain />
    </Section>
  );
};

const CheckoutForm = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Section title="Check Out a Book">
      <LabeledList>
        <LabeledList.Item label="Book">
          <Button onClick={() => act('editbook')}>
            {data.buffer_book || '—'}
          </Button>
        </LabeledList.Item>
        <LabeledList.Item label="Recipient">
          <Button onClick={() => act('editmob')}>
            {data.buffer_mob || '—'}
          </Button>
        </LabeledList.Item>
        <LabeledList.Item label="Checkout Date">
          {data.world_time_min}
        </LabeledList.Item>
        <LabeledList.Item label="Due Date">
          {data.world_time_min + data.checkout_period}
        </LabeledList.Item>
        <LabeledList.Item label="Period">
          <Button onClick={() => act('decreasetime')}>-</Button>{' '}
          <Box inline bold mx={1}>
            {data.checkout_period} min
          </Box>
          <Button onClick={() => act('increasetime')}>+</Button>
        </LabeledList.Item>
      </LabeledList>
      <Box mt={2}>
        <Button icon="check" color="good" onClick={() => act('checkout')}>
          Commit Entry
        </Button>
      </Box>
      <BackToMain />
    </Section>
  );
};

const SortHeader = ({ field, children }: { field: string; children: any }) => {
  const { data, act } = useBackend<Data>();
  return (
    <Table.Cell>
      <Button
        compact
        selected={data.sort_by === field}
        onClick={() => act('sort', { field })}
      >
        {children}
      </Button>
    </Table.Cell>
  );
};

const InternalArchive = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Section title="Internal Archive">
      {data.internal_archive.length === 0 ? (
        <Box color="bad" bold>
          ERROR: Internal archive empty. Contact System Administrator.
        </Box>
      ) : (
        <Table>
          <Table.Row header>
            <SortHeader field="author">AUTHOR</SortHeader>
            <SortHeader field="title">TITLE</SortHeader>
            <SortHeader field="category">CATEGORY</SortHeader>
            <Table.Cell />
          </Table.Row>
          {data.internal_archive.map((b) => (
            <Table.Row key={b.path}>
              <Table.Cell>{b.author}</Table.Cell>
              <Table.Cell>{b.name}</Table.Cell>
              <Table.Cell>{b.category}</Table.Cell>
              <Table.Cell>
                <Button onClick={() => act('hardprint', { path: b.path })}>
                  Order
                </Button>
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      )}
      <BackToMain />
    </Section>
  );
};

const Upload = () => {
  const { data, act } = useBackend<Data>();
  const cache = data.scanner_cache;
  return (
    <Section title="Upload a New Title">
      {!data.has_scanner ? (
        <Box color="bad" bold>
          No scanner found within wireless network range.
        </Box>
      ) : !cache ? (
        <Box color="bad" bold>
          No data found in scanner memory.
        </Box>
      ) : (
        <LabeledList>
          <LabeledList.Item label="Title">{cache.name}</LabeledList.Item>
          <LabeledList.Item label="Author">
            <Button onClick={() => act('setauthor')}>
              {cache.author || 'Anonymous'}
            </Button>
          </LabeledList.Item>
          <LabeledList.Item label="Category">
            <Button onClick={() => act('setcategory')}>
              {data.upload_category}
            </Button>
          </LabeledList.Item>
          <LabeledList.Item label="">
            <Button icon="upload" color="good" onClick={() => act('upload')}>
              Upload
            </Button>
          </LabeledList.Item>
        </LabeledList>
      )}
      <BackToMain />
    </Section>
  );
};

const ForbiddenVault = () => {
  const { act } = useBackend<Data>();
  return (
    <Section title="Forbidden Lore Vault v 1.3">
      <Box mb={1}>
        Are you absolutely sure you want to proceed? EldritchTomes Inc. takes no
        responsibilities for loss of sanity resulting from this action.
      </Box>
      <Button color="bad" onClick={() => act('arccheckout')}>
        Yes.
      </Button>{' '}
      <Button onClick={() => act('switchscreen', { screen: 0 })}>No.</Button>
    </Section>
  );
};

const ExternalArchive = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Section title="External Archive">
      {!data.has_db ? (
        <Box color="bad" bold>
          ERROR: Unable to contact External Archive. Please contact your system
          administrator for assistance.
        </Box>
      ) : (
        <>
          <Box mb={1}>
            <Button onClick={() => act('orderbyid')}>
              Order book by SS<sup>13</sup>BN
            </Button>
          </Box>
          <Table>
            <Table.Row header>
              <SortHeader field="author">AUTHOR</SortHeader>
              <SortHeader field="title">TITLE</SortHeader>
              <SortHeader field="category">CATEGORY</SortHeader>
              <Table.Cell />
            </Table.Row>
            {data.external_archive.map((b) => (
              <Table.Row key={b.id}>
                <Table.Cell>{b.author}</Table.Cell>
                <Table.Cell>{b.title}</Table.Cell>
                <Table.Cell>{b.category}</Table.Cell>
                <Table.Cell>
                  <Button onClick={() => act('targetid', { id: b.id })}>
                    Order
                  </Button>
                  {data.is_admin ? (
                    <>
                      {' '}
                      <Button
                        color="bad"
                        onClick={() => act('delid', { id: b.id })}
                      >
                        Del
                      </Button>
                    </>
                  ) : null}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </>
      )}
      <BackToMain />
    </Section>
  );
};
