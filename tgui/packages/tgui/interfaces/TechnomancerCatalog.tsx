// Technomancer catalog — TGUI.
//
// Five tabs (Functions / Equipment / Consumables / Assistance / Info)
// with structured item lists. Purchases and tab switches are dispatched
// via tgui_act, no embedded byond:// hrefs.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack, Tabs } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Spell = {
  name: string;
  desc: string;
  cost: number;
  spell_power_desc: string;
  enhancement_desc: string;
  category: string;
  hidden: BooleanLike;
};

type Item = {
  name: string;
  desc: string;
  cost: number;
};

type Data = {
  tab: number;
  spell_tab: string;
  budget: number;
  max_budget: number;
  spells: Spell[];
  equipment: Item[];
  consumables: Item[];
  assistance: Item[];
  spell_categories: string[];
};

const TAB_LABELS = [
  'Functions',
  'Equipment',
  'Consumables',
  'Assistance',
  'Info',
];

export const TechnomancerCatalog = () => {
  const { data, act } = useBackend<Data>();
  const { tab, budget, max_budget } = data;

  return (
    <Window width={620} height={680} title="Catalog">
      <Window.Content scrollable>
        <Section>
          <Tabs>
            {TAB_LABELS.map((label, i) => (
              <Tabs.Tab
                key={label}
                selected={tab === i}
                onClick={() => act('tab_choice', { tab: i })}
              >
                {label}
              </Tabs.Tab>
            ))}
          </Tabs>
          <Box mt={1}>
            Budget:{' '}
            <Box inline bold color={budget > 0 ? 'good' : 'bad'}>
              {budget} / {max_budget}
            </Box>
          </Box>
        </Section>
        {tab === 0 && <FunctionsTab />}
        {tab === 1 && <ItemsTab items={data.equipment} kind="equipment" />}
        {tab === 2 && <ItemsTab items={data.consumables} kind="consumables" />}
        {tab === 3 && <ItemsTab items={data.assistance} kind="assistance" />}
        {tab === 4 && <InfoTab />}
      </Window.Content>
    </Window>
  );
};

const FunctionsTab = () => {
  const { data, act } = useBackend<Data>();
  const { budget, spell_tab, spell_categories, spells } = data;
  const visible = spells.filter(
    (s) => !s.hidden && (spell_tab === 'All' || s.category === spell_tab),
  );
  return (
    <>
      <Section
        title="Functions"
        buttons={
          <Button
            color="bad"
            icon="undo"
            onClick={() => act('refund_functions')}
          >
            Refund Functions
          </Button>
        }
      >
        <Stack wrap>
          {spell_categories.map((c) => (
            <Stack.Item key={c}>
              <Button
                selected={spell_tab === c}
                onClick={() => act('spell_category', { category: c })}
              >
                {c}
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      </Section>
      <Stack vertical>
        {visible.map((s) => (
          <Stack.Item key={s.name}>
            <Section
              title={s.name}
              buttons={
                s.cost <= budget ? (
                  <Button
                    color="good"
                    onClick={() => act('spell_choice', { name: s.name })}
                  >
                    Purchase ({s.cost})
                  </Button>
                ) : (
                  <Box color="bad" bold>
                    Cannot afford ({s.cost})
                  </Box>
                )
              }
            >
              <Box italic color="label" mb={1}>
                {s.desc}
              </Box>
              {s.spell_power_desc ? (
                <Box color="purple">
                  <Box inline bold>
                    Spell Power:
                  </Box>{' '}
                  {s.spell_power_desc}
                </Box>
              ) : null}
              {s.enhancement_desc ? (
                <Box color="blue">
                  <Box inline bold>
                    Scepter Effect:
                  </Box>{' '}
                  {s.enhancement_desc}
                </Box>
              ) : null}
            </Section>
          </Stack.Item>
        ))}
      </Stack>
    </>
  );
};

const ItemsTab = (props: { items: Item[]; kind: string }) => {
  const { data, act } = useBackend<Data>();
  const { budget } = data;
  const { items } = props;
  return (
    <Stack vertical>
      {items.map((i) => (
        <Stack.Item key={i.name}>
          <Section
            title={i.name}
            buttons={
              i.cost <= budget ? (
                <Button
                  color="good"
                  onClick={() => act('item_choice', { name: i.name })}
                >
                  Purchase ({i.cost})
                </Button>
              ) : (
                <Box color="bad" bold>
                  Cannot afford ({i.cost})
                </Box>
              )
            }
          >
            <EmptyState>{i.desc}</EmptyState>
          </Section>
        </Stack.Item>
      ))}
    </Stack>
  );
};

const InfoTab = () => {
  return (
    <Section title="Manipulation Core Owner's Manual">
      <Box mb={1}>
        This brief entry in your catalog explains what everything does. The
        thing on your back is the <b>Manipulation Core</b>, or just a "Core". It
        does amazing things depending on which <b>functions</b> you've purchased
        for it. Don't lose your core.
      </Box>
      <Box mb={1}>
        Cores require <b>Energy</b>, which they generate themselves. Most
        functions cost energy. Some functions generate energy.
      </Box>
      <Box mb={1}>
        Power has consequences: <b>Instability</b>. It clings to you as you use
        functions; mild instability is annoying, heavy instability is fatal.
        Cores show a meter; instability fades on its own. High instability
        causes <b>Glow</b>, which spreads to others — stay away from anyone
        glowing.
      </Box>
      <Box mb={1}>
        Cores have a locking mechanism against forceful removal; death unlocks
        the core. A secondary safety zaps unauthorized carriers with massive
        instability.
      </Box>
      <Box mb={1}>
        <b>
          You can refund functions, equipment, and assistance items at your base
          only.
        </b>{' '}
        Use the Refund Functions button on the Functions tab. For equipment,
        strike it against the catalog.
      </Box>
      <Box mb={1}>
        Your blue robes and hat are somewhat protective against external
        instability sources (like Glow) and mundane electricity. For other
        threats, get real armor.
      </Box>
      <Box mb={1}>
        A function is a "spell" you hold and use on a target. The Scepter of
        Enhancement can boost certain functions (look for{' '}
        <Box inline color="blue">
          Scepter Effect:
        </Box>{' '}
        in the description). The core boosts functions with{' '}
        <Box inline color="purple">
          Spell Power:
        </Box>{' '}
        text. "Allies" means you, your apprentices, controlled entities, and
        friendly summons. One meter = one tile.
      </Box>
    </Section>
  );
};
