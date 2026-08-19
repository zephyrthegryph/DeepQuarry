import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Divider,
  Input,
  Section,
  Stack,
} from 'tgui-core/components';
import { createSearch } from 'tgui-core/string';

import type { Data, SupplyPack } from './types';

export const SupplyConsoleMenuOrder = (props) => {
  const { act, data } = useBackend<Data>();

  const {
    categories,
    supply_packs,
    contraband,
    supply_points,
    personal_balance,
    can_personal_order,
  } = data;

  const [activeCategory, setActiveCategory] = useState<string | null>(null);
  const [searchCategory, setSearchCategory] = useState<string>('');
  const [searchContent, setSearchContent] = useState<string>('');
  const [personalFunding, setPersonalFunding] = useState(false);

  const availableFunds = personalFunding ? personal_balance : supply_points;

  function sortPack(a: SupplyPack, b: SupplyPack) {
    if (a.cost < availableFunds && b.cost > availableFunds) return -1;
    if (a.cost > availableFunds && b.cost < availableFunds) return 1;

    return a.name.localeCompare(b.name);
  }

  const viewingPacks: SupplyPack[] = supply_packs
    .filter(
      (pack) =>
        pack.group === activeCategory && (!pack.contraband || !!contraband),
    )
    .sort((a, b) => sortPack(a, b));

  const categorySearch = createSearch(searchCategory);
  const contentSearch = createSearch<SupplyPack>(
    searchContent,
    (pack) => pack.name,
  );

  const filteredCategories = categories.filter(categorySearch);
  const filteredPack = viewingPacks.filter(contentSearch);

  return (
    <Stack fill>
      <Stack.Item basis="25%">
        <Section title="Categories" fill>
          <Input
            fluid
            placeholder={'Search for category...'}
            value={searchCategory}
            onChange={(val) => setSearchCategory(val)}
          />
          <Divider />
          <Section scrollable fill>
            {filteredCategories.map((category) => (
              <Button
                key={category}
                fluid
                selected={category === activeCategory}
                onClick={() => setActiveCategory(category)}
              >
                {category}
              </Button>
            ))}
          </Section>
        </Section>
      </Stack.Item>
      <Stack.Item grow ml={2}>
        <Section
          title="Contents"
          buttons={
            <Button.Checkbox
              checked={personalFunding}
              disabled={!can_personal_order}
              tooltip="Charge requested crates to your personal account immediately. Denied orders are refunded."
              onClick={() => setPersonalFunding(!personalFunding)}
            >
              Personal funds: {personal_balance} Thalers
            </Button.Checkbox>
          }
          fill
        >
          <Input
            fluid
            placeholder={'Search for pack...'}
            value={searchContent}
            onChange={(val) => setSearchContent(val)}
          />
          <Divider />
          <Section scrollable fill>
            {filteredPack.map((pack) => (
              <Box key={pack.name}>
                <Stack align="center" justify="flex-start">
                  <Stack.Item maxWidth="70%" basis="70%">
                    <Button
                      fluid
                      icon="shopping-cart"
                      ellipsis
                      color={pack.cost > availableFunds ? 'red' : undefined}
                      onClick={() =>
                        act('request_crate', {
                          ref: pack.ref,
                          personal: personalFunding,
                        })
                      }
                    >
                      {pack.name}
                    </Button>
                  </Stack.Item>
                  <Stack.Item>
                    <Button
                      color={pack.cost > availableFunds ? 'red' : undefined}
                      onClick={() =>
                        act('request_crate_multi', {
                          ref: pack.ref,
                          personal: personalFunding,
                        })
                      }
                    >
                      #
                    </Button>
                  </Stack.Item>
                  <Stack.Item>
                    <Button
                      color={pack.cost > supply_points ? 'red' : undefined}
                      onClick={() => act('view_crate', { crate: pack.ref })}
                    >
                      Info
                    </Button>
                  </Stack.Item>
                  <Stack.Item grow>{pack.cost} Thalers</Stack.Item>
                </Stack>
              </Box>
            ))}
            {/* Alternative collapsible style folders */}
            {/* {viewingPacks.map(pack => (
              <Collapsible title={pack.name} mb={-0.7}>
                <center>
                  {pack.manifest.map(item => (
                    <Box mb={0.5}>
                      {item}
                    </Box>
                  ))}
                  <Button
                    fluid
                    color="green"
                  >
                    {"Request - " + pack.cost + " Thalers"}
                  </Button>
                </center>
              </Collapsible>
            ))} */}
          </Section>
        </Section>
      </Stack.Item>
    </Stack>
  );
};
