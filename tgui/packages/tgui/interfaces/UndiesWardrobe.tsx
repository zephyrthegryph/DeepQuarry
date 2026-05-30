// Underwear dresser — TGUI.
//
// One row per underwear category. Click the category name to pick a
// different item; click each tweak chip to edit its parameter; click
// Remove to clear that category.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, LabeledList, Section, Stack } from 'tgui-core/components';

type Tweak = {
  ref: string;
  label: string;
};

type Category = {
  name: string;
  item_name: string;
  has_item: boolean;
  tweaks: Tweak[];
};

type Data = {
  categories: Category[];
};

export const UndiesWardrobe = () => {
  const { data, act } = useBackend<Data>();
  const { categories } = data;

  return (
    <Window width={520} height={420}>
      <Window.Content scrollable>
        <Section title="Underwear">
          <LabeledList>
            {categories.map((c) => (
              <LabeledList.Item key={c.name} label={c.name}>
                <Stack>
                  <Stack.Item>
                    <Button
                      onClick={() =>
                        act('change_underwear', { category: c.name })
                      }
                    >
                      {c.item_name}
                    </Button>
                  </Stack.Item>
                  {c.has_item
                    ? c.tweaks.map((t) => (
                        <Stack.Item key={t.ref}>
                          <Button
                            onClick={() =>
                              act('tweak', {
                                category: c.name,
                                tweak: t.ref,
                              })
                            }
                          >
                            {t.label}
                          </Button>
                        </Stack.Item>
                      ))
                    : null}
                  {c.has_item ? (
                    <Stack.Item>
                      <Button
                        icon="times"
                        color="bad"
                        onClick={() =>
                          act('remove_underwear', { category: c.name })
                        }
                      >
                        Remove
                      </Button>
                    </Stack.Item>
                  ) : null}
                </Stack>
              </LabeledList.Item>
            ))}
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
