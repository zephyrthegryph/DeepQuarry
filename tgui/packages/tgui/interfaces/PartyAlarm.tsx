// Party button — TGUI.
//
// Toggles a per-area party event. Non-AI/non-human users see scrambled
// labels but can still interact (matches the legacy stars() behavior).

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Data = {
  party_on: BooleanLike;
  timing: BooleanLike;
  time: number;
  scrambled: BooleanLike;
};

const scramble = (label: string, scrambled: boolean): string =>
  scrambled
    ? label
        .split('')
        .map((c) => (/[a-zA-Z]/.test(c) ? '*' : c))
        .join('')
    : label;

export const PartyAlarm = () => {
  const { data, act } = useBackend<Data>();
  const { party_on, timing, time, scrambled } = data;
  const sc = !!scrambled;

  const second = time % 60;
  const minute = (time - second) / 60;

  return (
    <Window width={420} height={220}>
      <Window.Content>
        <Section title={scramble('Party Button', sc)}>
          <LabeledList>
            <LabeledList.Item label={scramble('Party', sc)}>
              <Button
                icon={party_on ? 'frown' : 'music'}
                color={party_on ? 'bad' : 'good'}
                onClick={() => act(party_on ? 'reset' : 'alarm')}
              >
                {party_on
                  ? scramble('No Party :(', sc)
                  : scramble('PARTY!!!', sc)}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label={scramble('Timer', sc)}>
              <Button
                icon={timing ? 'pause' : 'play'}
                onClick={() => act('time', { value: timing ? 0 : 1 })}
              >
                {timing
                  ? scramble('Stop Time Lock', sc)
                  : scramble('Initiate Time Lock', sc)}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label={scramble('Time Left', sc)}>
              <Box inline>
                <Button onClick={() => act('tp', { value: -30 })}>-30</Button>{' '}
                <Button onClick={() => act('tp', { value: -1 })}>-1</Button>{' '}
                <Box inline bold mx={1}>
                  {minute ? `${minute}:` : ''}
                  {second.toString().padStart(2, '0')}
                </Box>
                <Button onClick={() => act('tp', { value: 1 })}>+1</Button>{' '}
                <Button onClick={() => act('tp', { value: 30 })}>+30</Button>
              </Box>
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
