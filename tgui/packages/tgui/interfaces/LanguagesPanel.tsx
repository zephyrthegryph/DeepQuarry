// Known Languages — structured TGUI panel.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';
import type {
  LanguagesPanelActions,
  LanguagesPanelData,
} from './generated/LanguagesPanel';

export const LanguagesPanel = () => {
  const { data, act } = useBackend<LanguagesPanelData, LanguagesPanelActions>();
  const { has_default, default_name, languages } = data;
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
              <Stack.Item key={l.id}>
                <Box>
                  <Box inline bold>
                    {l.name}
                  </Box>{' '}
                  <Box inline color="label">
                    ({l.custom_key || l.key})
                  </Box>{' '}
                  <Button
                    compact
                    onClick={() => act('edit_key', { language: l.id })}
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
                      onClick={() => act('set_default', { language: l.id })}
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
