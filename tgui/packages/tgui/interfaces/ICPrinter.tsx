import { useBackend, useSharedState } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  Section,
  Stack,
  Tabs,
} from 'tgui-core/components';
import type { ICPrinterActions, ICPrinterData } from './generated/ICPrinter';
import { StatBar } from 'tgui/components/StatBar';

type Data = ICPrinterData;

type category = Data['categories'][number];

type item = category['items'][number];

export const ICPrinter = (props) => {
  const { data, act } = useBackend<Data, ICPrinterActions>();

  const { metal, max_metal, metal_per_sheet, upgraded, can_clone } = data;

  return (
    <Window width={600} height={675}>
      <Window.Content>
        <Stack fill vertical>
          <Stack.Item>
            <Section fill title="Status">
              <Stack vertical>
                <Stack.Item>
                  <LabeledList>
                    <StatBar label="Metal" value={metal} maxValue={max_metal}>
                      {metal / metal_per_sheet} / {max_metal / metal_per_sheet}{' '}
                      sheets
                    </StatBar>
                    <LabeledList.Item label="Circuits Available">
                      {upgraded ? 'Advanced' : 'Regular'}
                    </LabeledList.Item>
                    <LabeledList.Item label="Assembly Cloning">
                      {can_clone ? 'Available' : 'Unavailable'}
                    </LabeledList.Item>
                  </LabeledList>
                </Stack.Item>
                {!!can_clone && (
                  <Stack.Item>
                    <Button
                      icon="file-import"
                      content="Import Circuit"
                      onClick={() => {
                        act('import_circuit');
                      }}
                      tooltip="Import a circuit design from a JSON file"
                    />
                  </Stack.Item>
                )}
                <Stack.Item>
                  Note: A red component name means that the printer must be
                  upgraded to create that component.
                </Stack.Item>
              </Stack>
            </Section>
          </Stack.Item>
          <Stack.Item>
            <ICPrinterCategories />
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};

function canBuild(item: item, data: Data) {
  if (!item.can_build) {
    return false;
  }

  if (item.cost > data.metal) {
    return false;
  }

  return true;
}

const ICPrinterCategories = (props) => {
  const { act, data } = useBackend<Data, ICPrinterActions>();

  const { categories = [] } = data;

  const [categoryTarget, setcategoryTarget] = useSharedState<string>(
    'categoryTarget',
    '',
  );

  const selectedCategory = categories.filter(
    (cat: category) => cat.name === categoryTarget,
  )[0];

  categories.sort((a, b) => a.name.localeCompare(b.name));

  return (
    <Section fill title="Circuits">
      <Stack fill>
        <Stack.Item mr={2} basis="20%">
          <Tabs vertical>
            {categories.map((cat) => (
              <Tabs.Tab
                selected={categoryTarget === cat.name}
                onClick={() => setcategoryTarget(cat.name)}
                key={cat.name}
              >
                {cat.name}
              </Tabs.Tab>
            ))}
          </Tabs>
        </Stack.Item>
        <Stack.Item grow>
          {selectedCategory ? (
            <Section fill scrollable>
              <LabeledList>
                {selectedCategory.items
                  .sort((a, b) => a.name.localeCompare(b.name))
                  .map((item) => (
                    <LabeledList.Item
                      key={item.name}
                      label={item.name}
                      labelColor={item.can_build ? 'good' : 'bad'}
                      buttons={
                        <Button
                          disabled={!canBuild(item, data)}
                          icon="print"
                          onClick={() => act('build', { build: item.path })}
                        >
                          Print
                        </Button>
                      }
                    >
                      {item.desc}
                    </LabeledList.Item>
                  ))}
              </LabeledList>
            </Section>
          ) : (
            <Box>No category selected.</Box>
          )}
        </Stack.Item>
      </Stack>
    </Section>
  );
};
