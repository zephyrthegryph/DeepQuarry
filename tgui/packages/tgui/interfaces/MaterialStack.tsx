import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  Collapsible,
  Input,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import { createSearch } from 'tgui-core/string';
import type {
  MaterialStackActions,
  MaterialStackData,
} from './generated/MaterialStack';

type RecipeTree = MaterialStackData['recipes'];
type Entry = RecipeTree[string];
type recipe = Exclude<Entry, RecipeTree>;

/** A recipe (it has a ref) rather than a group of further entries. */
const isRecipe = (entry: Entry): entry is recipe =>
  typeof entry.ref === 'number';

export const MaterialStack = (props) => {
  const { data } = useBackend<MaterialStackData, MaterialStackActions>();

  const { amount } = data;
  const recipes = data.recipes ?? {};
  const [searchText, setSearchText] = useState('');

  return (
    <Window width={400} height={600}>
      <Window.Content scrollable>
        <Section title={`Amount: ${amount}`}>
          <Stack vertical>
            <Stack.Item>
              <Input
                fluid
                placeholder="Search for recipe..."
                value={searchText}
                onChange={(val) => setSearchText(val)}
              />
            </Stack.Item>
            <Stack.Item>
              <RecipeList recipes={recipes} searchText={searchText} />
            </Stack.Item>
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};

const RecipeList = (props: { recipes: RecipeTree; searchText: string }) => {
  const { recipes, searchText } = props;

  const sortedKeys = Object.keys(recipes).sort();

  const searcher = createSearch<string>(searchText, (recipe) => {
    return recipe;
  });

  const filteredKeys = sortedKeys.filter(searcher);

  // Shunt all categories to the top.
  // We're not using this for now, keeping it here in case someone really hates color coding later.
  // let nonCategories = sortedKeys.filter(item => recipes[item].ref !== undefined);
  // let categories = sortedKeys.filter(item => recipes[item].ref === undefined);

  return filteredKeys.map((title, index) => {
    // if (title === "--DIVIDER--") {
    //   return (
    //     <Box mt={1} mb={1}>
    //       <Divider />
    //     </Box>
    //   );
    // }
    const recipe = recipes[title];
    if (!isRecipe(recipe)) {
      return (
        <Collapsible key={index} ml={1} mb={-0.7} color="label" title={title}>
          <Box ml={1}>
            <RecipeList recipes={recipe} searchText={searchText} />
          </Box>
        </Collapsible>
      );
    } else {
      return <Recipe key={index} title={title} recipe={recipe} />;
    }
  });
};

const buildMultiplier = (recipe: recipe, amount: number) => {
  if (recipe.req_amount > amount) {
    return 0;
  }

  return Math.floor(amount / recipe.req_amount);
};

const Multipliers = (props) => {
  const { act, data } = useBackend<MaterialStackData, MaterialStackActions>();

  const { recipe, maxMultiplier } = props;

  const maxM = Math.min(
    maxMultiplier,
    Math.floor(recipe.max_res_amount / recipe.res_amount),
  );

  const multipliers = [5, 10, 25];

  const finalResult: React.JSX.Element[] = [];

  for (const multiplier of multipliers) {
    if (maxM >= multiplier) {
      finalResult.push(
        <Button
          onClick={() =>
            act('make', {
              ref: recipe.ref,
              multiplier: multiplier,
            })
          }
        >
          {`${multiplier * recipe.res_amount}x`}
        </Button>,
      );
    }
  }

  if (multipliers.indexOf(maxM) === -1) {
    finalResult.push(
      <Button
        onClick={() =>
          act('make', {
            ref: recipe.ref,
            multiplier: maxM,
          })
        }
      >
        {`${maxM * recipe.res_amount}x`}
      </Button>,
    );
  }

  return finalResult;
};

const Recipe = (props: { recipe: recipe; title: string }) => {
  const { act, data } = useBackend<MaterialStackData, MaterialStackActions>();

  const { amount } = data;

  const { recipe, title } = props;

  const { res_amount, max_res_amount, req_amount, ref } = recipe;

  let buttonName = title;
  buttonName += ' (';
  buttonName += `${req_amount} `;
  buttonName += `sheet${req_amount > 1 ? 's' : ''}`;
  buttonName += ')';

  if (res_amount > 1) {
    buttonName = `${res_amount}x ${buttonName}`;
  }

  const maxMultiplier = buildMultiplier(recipe, amount);

  return (
    <Box>
      <Table>
        <Table.Row>
          <Table.Cell>
            <Button
              fluid
              disabled={!maxMultiplier}
              icon="wrench"
              onClick={() =>
                act('make', {
                  ref: recipe.ref,
                  multiplier: 1,
                })
              }
            >
              {buttonName}
            </Button>
          </Table.Cell>
          {max_res_amount > 1 && maxMultiplier > 1 && (
            <Table.Cell collapsing>
              <Multipliers recipe={recipe} maxMultiplier={maxMultiplier} />
            </Table.Cell>
          )}
        </Table.Row>
      </Table>
    </Box>
  );
};
