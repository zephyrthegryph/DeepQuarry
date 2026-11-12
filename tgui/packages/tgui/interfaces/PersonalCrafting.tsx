import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  Dimmer,
  Icon,
  Input,
  LabeledList,
  Section,
  Stack,
  Tabs,
} from 'tgui-core/components';
import { createSearch } from 'tgui-core/string';
import { ProductConfigurator } from './Fabrication/SelectableRecipe';
import type { Design } from './Fabrication/Types';
import type {
  PersonalCraftingActions,
  PersonalCraftingData,
} from './generated/PersonalCrafting';
import { Label } from 'tgui/components/Label';

type Recipe = Extract<
  PersonalCraftingData['crafting_recipes'][string],
  unknown[]
>[number];

type UiCategory = { name: string; category: string; subcategory?: string };
type UiRecipe = Recipe & { category: string };

const getUiEntries = (
  craftingRecipes: PersonalCraftingData['crafting_recipes'],
) => {
  const categories: UiCategory[] = [];
  const recipes: UiRecipe[] = [];
  for (const category of Object.keys(craftingRecipes)) {
    const entries = craftingRecipes[category];
    if (Array.isArray(entries)) {
      categories.push({ name: category, category });
      for (const recipe of entries) recipes.push({ ...recipe, category });
    } else {
      for (const subcategory of Object.keys(entries)) {
        const subRecipes = entries[subcategory];
        if (!Array.isArray(subRecipes)) continue;
        categories.push({ name: subcategory, category, subcategory });
        for (const recipe of subRecipes)
          recipes.push({ ...recipe, category: subcategory });
      }
    }
  }
  return { categories, recipes };
};

export const PersonalCrafting = () => {
  const { act, data } = useBackend<
    PersonalCraftingData,
    PersonalCraftingActions
  >();
  const [searchText, setSearchText] = useState('');
  const { categories, recipes } = getUiEntries(data.crafting_recipes ?? {});
  const [tab, setTab] = useState(categories[0]?.name);
  const search = createSearch<Recipe>(searchText, (recipe) => recipe.name);
  const shown = recipes.filter(
    (recipe) => recipe.category === tab && (!searchText || search(recipe)),
  );

  return (
    <Window title="Crafting" width={1050} height={720}>
      <Window.Content>
        {!!data.busy && (
          <Dimmer fontSize="32px">
            <Icon name="cog" spin /> Crafting...
          </Dimmer>
        )}
        <Stack fill>
          <Stack.Item width="180px">
            <Section fill title="Categories">
              <Tabs vertical>
                {categories.map((category) => (
                  <Tabs.Tab
                    key={`${category.category}-${category.name}`}
                    selected={category.name === tab}
                    onClick={() => {
                      setTab(category.name);
                      act('set_category', {
                        category: category.category,
                        subcategory: category.subcategory,
                      });
                    }}
                  >
                    {category.name}
                  </Tabs.Tab>
                ))}
              </Tabs>
            </Section>
          </Stack.Item>
          <Stack.Item grow>
            <Section
              fill
              title={tab ?? 'Recipes'}
              buttons={
                <Button.Checkbox
                  checked={data.display_craftable_only}
                  onClick={() => act('toggle_recipes')}
                >
                  Craftable only
                </Button.Checkbox>
              }
            >
              <Stack vertical fill>
                <Stack.Item>
                  <Input
                    fluid
                    value={searchText}
                    placeholder="Search recipes..."
                    onChange={setSearchText}
                  />
                </Stack.Item>
                <Stack.Item grow style={{ minHeight: 0 }}>
                  <CraftingWorkspace recipes={shown} />
                </Stack.Item>
              </Stack>
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};

const CraftingWorkspace = ({ recipes }: { recipes: UiRecipe[] }) => {
  const { act, data } = useBackend<
    PersonalCraftingData,
    PersonalCraftingActions
  >();
  const visible = data.display_craftable_only
    ? recipes.filter((recipe) => data.craftability[recipe.ref])
    : recipes;
  const [selectedRef, setSelectedRef] = useState<number | null>(null);
  const selected =
    visible.find((recipe) => recipe.ref === selectedRef) ?? visible[0];
  const available = Object.fromEntries(
    (data.materialChoices ?? []).map((material) => [
      material.id,
      material.sheets * 100,
    ]),
  );

  return (
    <Stack fill>
      <Stack.Item basis="42%" style={{ overflowY: 'auto', minHeight: 0 }}>
        <Stack vertical>
          {visible.map((recipe) => (
            <Stack.Item key={recipe.ref}>
              <Button
                fluid
                selected={selected?.ref === recipe.ref}
                disabled={!data.craftability[recipe.ref]}
                onClick={() => setSelectedRef(recipe.ref)}
              >
                <Stack align="center">
                  <Stack.Item grow>
                    <Box bold>{recipe.name}</Box>
                    <Label fontSize="11px">{recipe.req_text}</Label>
                  </Stack.Item>
                  <Stack.Item>
                    <Icon name="chevron-right" />
                  </Stack.Item>
                </Stack>
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      </Stack.Item>
      <Stack.Item grow>
        {!selected ? (
          <Section fill>
            <Label>No recipes in this category.</Label>
          </Section>
        ) : selected.material_slots?.length ? (
          <ProductConfigurator
            key={selected.ref}
            design={
              {
                name: selected.name,
                desc: [
                  selected.req_text,
                  selected.tool_text && `Tools: ${selected.tool_text}`,
                ]
                  .filter(Boolean)
                  .join(' · '),
                id: String(selected.ref),
                icon: '',
                categories: [],
                cost: {},
                materialConfigurable: 1,
                materialSlots: selected.material_slots,
              } satisfies Design
            }
            available={available}
            materialChoices={data.materialChoices ?? []}
            SHEET_MATERIAL_AMOUNT={100}
            single
            actionLabel="Craft"
            onBuild={(materialSlots) =>
              act('make', { recipe: selected.ref, materialSlots })
            }
          />
        ) : (
          <Section
            fill
            title={selected.name}
            buttons={
              <Button
                icon="cog"
                color="good"
                disabled={!data.craftability[selected.ref]}
                onClick={() => act('make', { recipe: selected.ref })}
              >
                Craft
              </Button>
            }
          >
            <LabeledList>
              {!!selected.req_text && (
                <LabeledList.Item label="Required">
                  {selected.req_text}
                </LabeledList.Item>
              )}
              {!!selected.catalyst_text && (
                <LabeledList.Item label="Catalyst">
                  {selected.catalyst_text}
                </LabeledList.Item>
              )}
              {!!selected.tool_text && (
                <LabeledList.Item label="Tools">
                  {selected.tool_text}
                </LabeledList.Item>
              )}
            </LabeledList>
          </Section>
        )}
      </Stack.Item>
    </Stack>
  );
};
