// Torban (ToR exit-address ban list) — structured TGUI read-only viewer.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Data = {
  addresses: string[];
};

export const TorbanList = () => {
  const { data } = useBackend<Data>();
  const { addresses } = data;
  return (
    <Window width={460} height={500} title="Torban">
      <Window.Content scrollable>
        <Section title={`ToR Banned Addresses (${addresses.length})`}>
          {addresses.length === 0 ? (
            <EmptyState>No addresses in list.</EmptyState>
          ) : (
            <Stack vertical>
              {addresses.map((a, i) => (
                <Stack.Item key={i}>
                  <Box color="label" inline>
                    #{i + 1}
                  </Box>{' '}
                  <Box inline>{a}</Box>
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
