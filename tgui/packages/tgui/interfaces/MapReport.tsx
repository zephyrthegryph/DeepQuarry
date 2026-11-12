// Map verify report — structured TGUI panel for admin map-load diagnostics.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { Label } from 'tgui/components/Label';

type BadPath = { path: string; keys: string[] };
type BadKey = { key: string; messages: string[] };

type Data = {
  original_path: string;
  crashed: BooleanLike;
  loadable: BooleanLike;
  bad_paths: BadPath[];
  bad_keys: BadKey[];
};

export const MapReport = () => {
  const { data } = useBackend<Data>();
  const {
    original_path,
    crashed,
    loadable,
    bad_paths = [],
    bad_keys = [],
  } = data;
  return (
    <Window width={680} height={560} title={`Map Report: ${original_path}`}>
      <Window.Content scrollable>
        <Section title="Status">
          <LabeledList>
            <LabeledList.Item label="Map">{original_path}</LabeledList.Item>
            <LabeledList.Item
              label="Validation"
              color={crashed ? 'bad' : 'good'}
            >
              {crashed ? 'Crashed — check runtime logs' : 'Completed'}
            </LabeledList.Item>
            <LabeledList.Item
              label="Loadable"
              color={loadable ? 'good' : 'bad'}
            >
              {loadable ? 'Yes' : 'No — missing turfs or areas'}
            </LabeledList.Item>
          </LabeledList>
        </Section>
        {bad_paths.length > 0 ? (
          <Section title={`Bad Paths (${bad_paths.length})`}>
            <Stack vertical>
              {bad_paths.map((p) => (
                <Stack.Item key={p.path}>
                  <Box>
                    <b>{p.path}</b>
                  </Box>
                  <Label ml={1}>
                    used in {p.keys.length}: {p.keys.join(', ')}
                  </Label>
                </Stack.Item>
              ))}
            </Stack>
          </Section>
        ) : null}
        {bad_keys.length > 0 ? (
          <Section title={`Bad Keys (${bad_keys.length})`}>
            <Stack vertical>
              {bad_keys.map((k) => (
                <Stack.Item key={k.key}>
                  <Box>
                    <b>{k.key}</b>
                  </Box>
                  {k.messages.length === 1 ? (
                    <Label ml={1}>{k.messages[0]}</Label>
                  ) : (
                    <Box ml={1}>
                      {k.messages.map((m, i) => (
                        <Label key={i}>• {m}</Label>
                      ))}
                    </Box>
                  )}
                </Stack.Item>
              ))}
            </Stack>
          </Section>
        ) : null}
      </Window.Content>
    </Window>
  );
};
