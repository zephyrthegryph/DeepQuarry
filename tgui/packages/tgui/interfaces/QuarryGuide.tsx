// Deep Quarry field guide — TGUI.
//
// Read-only player guide. DM side ships the entire topic list once; topic
// selection is local state, so navigation does not roundtrip.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import { HtmlRenderer } from './common/HtmlRenderer';

type Topic = {
  key: string;
  title: string;
  body: string;
};

type Data = {
  topics: Topic[];
};

export const QuarryGuide = () => {
  const { data } = useBackend<Data>();
  const topics = data.topics ?? [];
  const [selectedKey, setSelectedKey] = useState<string>(topics[0]?.key ?? '');
  const current = topics.find((t) => t.key === selectedKey) ?? topics[0];

  return (
    <Window width={640} height={560}>
      <Window.Content>
        <Stack fill>
          <Stack.Item width="180px">
            <Section fill scrollable title="Topics">
              <Stack vertical>
                {topics.map((t) => (
                  <Stack.Item key={t.key}>
                    <Button
                      fluid
                      selected={t.key === selectedKey}
                      onClick={() => setSelectedKey(t.key)}
                    >
                      {t.title}
                    </Button>
                  </Stack.Item>
                ))}
              </Stack>
            </Section>
          </Stack.Item>
          <Stack.Item grow>
            <Section fill scrollable title={current?.title ?? ''}>
              {current ? (
                <HtmlRenderer html={current.body} />
              ) : (
                <Box color="label">No topic selected.</Box>
              )}
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
