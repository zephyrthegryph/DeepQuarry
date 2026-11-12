import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Button,
  Collapsible,
  LabeledList,
  Section,
  Stack,
} from 'tgui-core/components';
import { toTitleCase } from 'tgui-core/string';
import type {
  SeedStorageActions,
  SeedStorageData,
} from './generated/SeedStorage';

export const SeedStorage = (props) => {
  const { act, data } = useBackend<SeedStorageData, SeedStorageActions>();

  const { seeds = [] } = data;

  seeds.sort((a, b) =>
    a.name.toLowerCase().localeCompare(b.name.toLowerCase()),
  );

  return (
    <Window width={600} height={760}>
      <Window.Content scrollable>
        <Section title="Seeds">
          {seeds.map((seed) => (
            <Stack mt={-1} key={seed.name + seed.uid}>
              <Stack.Item basis="60%">
                <Collapsible title={`${toTitleCase(seed.name)} #${seed.uid}`}>
                  <Section width="165%" title="Traits">
                    <LabeledList>
                      {Object.keys(seed.traits).map((key) => (
                        <LabeledList.Item label={toTitleCase(key)} key={key}>
                          {seed.traits[key]}
                        </LabeledList.Item>
                      ))}
                    </LabeledList>
                  </Section>
                </Collapsible>
              </Stack.Item>
              <Stack.Item mt={0.4}>{seed.amount} Remaining</Stack.Item>
              <Stack.Item grow>
                <Button
                  fluid
                  icon="download"
                  onClick={() => act('vend', { id: seed.id })}
                >
                  Vend
                </Button>
              </Stack.Item>
              <Stack.Item grow>
                <Button
                  fluid
                  icon="trash"
                  onClick={() => act('purge', { id: seed.id })}
                >
                  Purge
                </Button>
              </Stack.Item>
            </Stack>
          ))}
        </Section>
      </Window.Content>
    </Window>
  );
};
