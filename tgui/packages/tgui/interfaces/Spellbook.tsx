// Wizard spellbook — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Spell = {
  id: string;
  name: string;
  cooldown: number;
  desc: string;
};

type Artefact = {
  id: string;
  name: string;
  desc: string;
};

type NoClothes = {
  id: string;
  name: string;
  desc: string;
};

type Data = {
  temp: string;
  uses: number;
  max_uses: number;
  can_rememorize: BooleanLike;
  spells: Spell[];
  artefacts: Artefact[];
  noclothes: NoClothes;
};

export const Spellbook = () => {
  const { data, act } = useBackend<Data>();
  const { temp, uses, max_uses, can_rememorize, spells, artefacts, noclothes } =
    data;
  if (temp) {
    return (
      <Window width={520} height={260} title="The Book of Spells">
        <Window.Content scrollable>
          <Section>
            <Box>{temp}</Box>
            <Box mt={1}>
              <Button onClick={() => act('clear_temp')}>Clear</Button>
            </Box>
          </Section>
        </Window.Content>
      </Window>
    );
  }
  return (
    <Window width={620} height={620} title="The Book of Spells">
      <Window.Content scrollable>
        <Section title="The Book of Spells">
          <LabeledList>
            <LabeledList.Item label="Spells left">
              {uses} / {max_uses}
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1} italic color="label">
            The number after the spell name is the cooldown time.
          </Box>
        </Section>
        <Section title="Memorize a Spell">
          <Stack vertical>
            {spells.map((s) => (
              <Stack.Item key={s.id}>
                <Button onClick={() => act('choose', { id: s.id })}>
                  {s.name} ({s.cooldown})
                </Button>
                <Box ml={1} italic color="label">
                  {s.desc}
                </Box>
              </Stack.Item>
            ))}
            <Stack.Item>
              <Button onClick={() => act('choose', { id: noclothes.id })}>
                {noclothes.name}
              </Button>
              <Box ml={1} italic color="label">
                {noclothes.desc}
              </Box>
            </Stack.Item>
          </Stack>
        </Section>
        <Section title="Artefacts">
          <Box italic color="label" mb={1}>
            Powerful items imbued with eldritch magics. Summoning one counts
            towards your maximum number of spells. Only experienced wizards
            should attempt to wield them.
          </Box>
          <Stack vertical>
            {artefacts.map((a) => (
              <Stack.Item key={a.id}>
                <Button onClick={() => act('choose', { id: a.id })}>
                  {a.name}
                </Button>
                <Box ml={1} italic color="label">
                  {a.desc}
                </Box>
              </Stack.Item>
            ))}
          </Stack>
        </Section>
        {can_rememorize ? (
          <Section>
            <Button
              icon="rotate-right"
              onClick={() => act('choose', { id: 'rememorize' })}
            >
              Re-memorize Spells
            </Button>
          </Section>
        ) : null}
      </Window.Content>
    </Window>
  );
};
