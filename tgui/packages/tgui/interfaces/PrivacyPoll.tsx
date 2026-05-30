// Player privacy poll — TGUI.
//
// One-shot consent screen surfaced when a player who has never voted
// logs in. Five mutually exclusive choices; clicking any closes the
// window. "later" just closes without writing to the DB.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';

type Choice = {
  key: string;
  label: string;
  desc: string;
};

const CHOICES: Choice[] = [
  {
    key: 'signed',
    label: 'Signed stats gathering',
    desc: 'Pick this if you think usernames should be logged with stats. Allows personalized stats and polls.',
  },
  {
    key: 'anonymous',
    label: 'Anonymous stats gathering',
    desc: 'Pick this if you think only hashed (indecipherable) usernames should be logged. No personalized stats, but in-game polls still work.',
  },
  {
    key: 'nostats',
    label: 'No stats gathering',
    desc: "Pick this if you don't want player-specific stats gathered. No personalized stats or polls.",
  },
  {
    key: 'later',
    label: 'Ask again later',
    desc: 'This poll will come back up next round.',
  },
  {
    key: 'abstain',
    label: "Don't ask again",
    desc: "Only pick this if you're fine with whatever option wins.",
  },
];

export const PrivacyPoll = () => {
  const { act } = useBackend();
  return (
    <Window width={520} height={520} title="Player Poll — Privacy">
      <Window.Content scrollable>
        <Section title="Player Poll">
          <Box bold mb={1}>
            We would like to expand our stats gathering.
          </Box>
          <Box mb={1}>
            This involves gathering data about player behavior, play styles,
            unique player numbers, play times, etc. Data like that cannot be
            gathered fully anonymously, which is why we&apos;re asking how
            you&apos;d feel if player-specific data was gathered. Before any of
            this actually happens a privacy policy will be discussed, but first
            we&apos;d preliminarily like to know how you feel about the concept.
          </Box>
          <Box bold mb={2}>
            How do you feel about the game gathering player-specific statistics?
            This includes statistics about individual players as well as in-game
            polling and opinion requests.
          </Box>

          <Stack vertical>
            {CHOICES.map((c) => (
              <Stack.Item key={c.key}>
                <Button fluid onClick={() => act('vote', { choice: c.key })}>
                  {c.label}
                </Button>
                <Box mt={1} mb={1} color="label">
                  {c.desc}
                </Box>
              </Stack.Item>
            ))}
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};
