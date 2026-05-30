// Admin Unban panel — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Ban = {
  key_id: string;
  key: string;
  id: string;
  ip: string;
  reason: string;
  by: string;
  expiry: string;
};

type Data = {
  bans: Ban[];
  count: number;
};

export const UnbanPanel = () => {
  const { data, act } = useBackend<Data>();
  const { bans, count } = data;
  return (
    <Window width={760} height={620} title={`Unban (${count})`}>
      <Window.Content scrollable>
        <Section title={`Bans — ${count} total`}>
          {bans.length === 0 ? (
            <EmptyState>No bans.</EmptyState>
          ) : (
            <Stack vertical>
              {bans.map((b) => (
                <Stack.Item key={b.key_id}>
                  <Box>
                    <Button
                      compact
                      color="good"
                      onClick={() => act('unban', { key_id: b.key_id })}
                    >
                      Unban
                    </Button>{' '}
                    <Button
                      compact
                      onClick={() => act('edit', { key_id: b.key_id })}
                    >
                      Edit
                    </Button>{' '}
                    <Box inline bold>
                      {b.key}
                    </Box>
                  </Box>
                  <Box ml={1} mt="2px">
                    <LabeledList>
                      <LabeledList.Item label="ComputerID">
                        {b.id}
                      </LabeledList.Item>
                      <LabeledList.Item label="IP">{b.ip}</LabeledList.Item>
                      <LabeledList.Item label="Expires">
                        {b.expiry}
                      </LabeledList.Item>
                      <LabeledList.Item label="By">{b.by}</LabeledList.Item>
                      <LabeledList.Item label="Reason">
                        {b.reason}
                      </LabeledList.Item>
                    </LabeledList>
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
