// Mind Memory viewer — structured TGUI for the player's antagonist memory.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';
import { HtmlRenderer } from './common/HtmlRenderer';

type Objective = { text: string };

type Data = {
  name: string;
  memory: string;
  ambitions: string;
  objectives: Objective[];
};

export const MindMemory = () => {
  const { data } = useBackend<Data>();
  const { name, memory, ambitions, objectives } = data;
  return (
    <Window width={520} height={520} title={`Memory: ${name}`}>
      <Window.Content scrollable>
        <Section title={`${name}'s Memory`}>
          {memory ? (
            <HtmlRenderer html={memory} />
          ) : (
            <EmptyState>No memories recorded.</EmptyState>
          )}
        </Section>
        {objectives.length > 0 ? (
          <Section title="Objectives">
            <Stack vertical>
              {objectives.map((o, i) => (
                <Stack.Item key={i}>
                  <Box bold>Objective #{i + 1}</Box>
                  <Box ml={1}>{o.text}</Box>
                </Stack.Item>
              ))}
            </Stack>
          </Section>
        ) : null}
        {ambitions ? (
          <Section title="Ambitions">
            <Box>{ambitions}</Box>
          </Section>
        ) : null}
      </Window.Content>
    </Window>
  );
};
