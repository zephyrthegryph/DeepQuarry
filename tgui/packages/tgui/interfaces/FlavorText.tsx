// Set Flavour Text — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Part = {
  key: string;
  label: string;
  preview: string;
};

type Data = {
  parts: Part[];
};

export const FlavorText = () => {
  const { data, act } = useBackend<Data>();
  const { parts } = data;
  return (
    <Window width={560} height={500} title="Update Flavour Text">
      <Window.Content scrollable>
        <Section
          title="Update Flavour Text"
          buttons={
            <Button color="good" onClick={() => act('done')} icon="check">
              Done
            </Button>
          }
        >
          <Stack vertical>
            {parts.map((p) => (
              <Stack.Item key={p.key}>
                <Stack>
                  <Stack.Item basis="80px">
                    <Button
                      fluid
                      compact
                      onClick={() => act('edit', { key: p.key })}
                    >
                      {p.label}
                    </Button>
                  </Stack.Item>
                  <Stack.Item grow>
                    {p.preview ? (
                      <Box color="label">{p.preview}</Box>
                    ) : (
                      <EmptyState>(not set)</EmptyState>
                    )}
                  </Stack.Item>
                </Stack>
              </Stack.Item>
            ))}
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};
