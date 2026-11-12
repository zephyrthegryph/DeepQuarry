// Wizard spellbook — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { SpellbookActions, SpellbookData } from './generated/Spellbook';
import { Label } from 'tgui/components/Label';

type Data = SpellbookData;

export const Spellbook = () => {
  const { data, act } = useBackend<Data, SpellbookActions>();
  const {
    temp,
    uses,
    max_uses,
    can_rememorize,
    spells = [],
    artefacts = [],
    noclothes,
  } = data;
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
          <Label mt={1} italic>
            The number after the spell name is the cooldown time.
          </Label>
        </Section>
        <Section title="Memorize a Spell">
          <Stack vertical>
            {spells.map((s) => (
              <Stack.Item key={s.id}>
                <Button onClick={() => act('choose', { id: s.id })}>
                  {s.name} ({s.cooldown})
                </Button>
                <Label ml={1} italic>
                  {s.desc}
                </Label>
              </Stack.Item>
            ))}
            <Stack.Item>
              <Button onClick={() => act('choose', { id: noclothes.id })}>
                {noclothes?.name}
              </Button>
              <Label ml={1} italic>
                {noclothes?.desc}
              </Label>
            </Stack.Item>
          </Stack>
        </Section>
        <Section title="Artefacts">
          <Label italic mb={1}>
            Powerful items imbued with eldritch magics. Summoning one counts
            towards your maximum number of spells. Only experienced wizards
            should attempt to wield them.
          </Label>
          <Stack vertical>
            {artefacts.map((a) => (
              <Stack.Item key={a.id}>
                <Button onClick={() => act('choose', { id: a.id })}>
                  {a.name}
                </Button>
                <Label ml={1} italic>
                  {a.desc}
                </Label>
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
