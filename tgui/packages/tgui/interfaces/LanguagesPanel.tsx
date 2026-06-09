// Known Languages — structured TGUI panel.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type LanguageRow = {
  ref: string;
  name: string;
  key: string;
  custom_key: string | null;
  description: string;
  can_speak: BooleanLike;
  is_default: BooleanLike;
};

type Data = {
  prefix: string;
  has_default: BooleanLike;
  default_name: string | null;
  languages: LanguageRow[];
};

export const LanguagesPanel = () => {
  const { data, act } = useBackend<Data>();
  const { prefix, has_default, default_name, languages } = data;
  return (
    <Window width={560} height={620} title="Known Languages">
      <Window.Content scrollable>
        <Section title="Default Language">
          {has_default ? (
            <>
              <Box mb={1}>
                Current default:{' '}
                <Box inline bold>
                  {default_name}
                </Box>
              </Box>
              <Button onClick={() => act('reset_default')} icon="rotate-right">
                Reset
              </Button>
            </>
          ) : (
            <EmptyState>No default language set.</EmptyState>
          )}
        </Section>
        <Section title="Languages">
          <Stack vertical>
            {languages.map((l) => (
              <Stack.Item key={l.ref}>
                <Box>
                  <Box inline bold>
                    {l.name}
                  </Box>{' '}
                  <Box inline color="label">
                    ({prefix}
                    {l.key}
                    {l.custom_key ? ` ${prefix}${l.custom_key}` : ''})
                  </Box>{' '}
                  <Button
                    compact
                    onClick={() => act('edit_key', { ref: l.ref })}
                  >
                    Edit Custom Key
                  </Button>{' '}
                  {l.is_default ? (
                    <Box inline color="good">
                      default
                    </Box>
                  ) : l.can_speak ? (
                    <Button
                      compact
                      onClick={() => act('set_default', { ref: l.ref })}
                    >
                      Set Default
                    </Button>
                  ) : (
                    <Box inline color="bad">
                      cannot speak
                    </Box>
                  )}
                </Box>
                <Box ml={1} mt="2px" italic color="label">
                  {l.description}
                </Box>
              </Stack.Item>
            ))}
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};
