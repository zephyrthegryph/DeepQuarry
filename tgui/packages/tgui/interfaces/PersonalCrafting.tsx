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
import type { BooleanLike } from 'tgui-core/react';
import { createSearch } from 'tgui-core/string';
import { ProductConfigurator } from './Fabrication/SelectableRecipe';
import type { Design, MaterialChoice, MaterialSlot } from './Fabrication/Types';

type Data = {
  busy: BooleanLike;
  display_craftable_only: BooleanLike;
  display_compact: BooleanLike;
  craftability: Record<string, number>;
  crafting_recipes: Record<string, Recipe[]>;
  materialChoices: MaterialChoice[];
};

type Recipe = {
  name: string;
  ref: string;
  req_text: string;
  catalyst_text: string;
  tool_text: string;
  has_subcats: BooleanLike;
  material_slots: MaterialSlot[];
};

type UiCategory = { name: string; category: string; subcategory?: string };
type UiRecipe = Required<Recipe & { category: string }>;

const getUiEntries = (craftingRecipes: Record<string, Recipe[]>) => {
  const categories: UiCategory[] = [];
  const recipes: UiRecipe[] = [];
  for (const category of Object.keys(craftingRecipes)) {
    const entries = craftingRecipes[category];
    if ('has_subcats' in entries) {
      for (const subcategory of Object.keys(entries)) {
        if (subcategory === 'has_subcats') continue;
        categories.push({ name: subcategory, category, subcategory });
        for (const recipe of entries[subcategory])
          recipes.push({ ...recipe, category: subcategory });
      }
    } else {
      categories.push({ name: category, category });
      for (const recipe of entries) recipes.push({ ...recipe, category });
    }
  }
  return { categories, recipes };
};

export const PersonalCrafting = () => {
  const { act, data } = useBackend<Data>();
  const [searchText, setSearchText] = useState('');
  const { categories, recipes } = getUiEntries(data.crafting_recipes || {});
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
              <Input
                fluid
                value={searchText}
                placeholder="Search recipes..."
                onChange={setSearchText}
                mb={1}
              />
              <CraftingWorkspace recipes={shown} />
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};

const CraftingWorkspace = ({ recipes }: { recipes: UiRecipe[] }) => {
  const { act, data } = useBackend<Data>();
  const visible = data.display_craftable_only
    ? recipes.filter((recipe) => data.craftability[recipe.ref])
    : recipes;
  const [selectedRef, setSelectedRef] = useState<string | null>(null);
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
      <Stack.Item basis="42%" style={{ overflowY: 'auto' }}>
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
                    <Box color="label" fontSize="11px">
                      {recipe.req_text}
                    </Box>
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
            <Box color="label">No recipes in this category.</Box>
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
                id: selected.ref,
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
