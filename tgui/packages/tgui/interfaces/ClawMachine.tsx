import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList } from 'tgui-core/components';
import type {
  ClawMachineActions,
  ClawMachineData,
} from './generated/ClawMachine';
import { StatBar } from 'tgui/components/StatBar';

type Data = ClawMachineData;

export const ClawMachine = (props) => {
  const { act, data } = useBackend<Data, ClawMachineActions>();
  const { wintick, instructions, gameStatus, winscreen } = data;

  let body;

  if (gameStatus === 'CLAWMACHINE_NEW') {
    body = (
      <Box align="center">
        <br /> <hr />
        <b>Pay to Play!</b> <br /> <hr />
        {instructions}
        <br /> <hr /> <br />
        <Button onClick={() => act('newgame')}>Start</Button>
      </Box>
    );
  } else if (gameStatus === 'CLAWMACHINE_END') {
    body = (
      <Box align="center">
        <br /> <hr />
        <b>Thank you for playing!</b> <br /> <hr />
        {winscreen}
        <br /> <hr /> <br />
        <Button onClick={() => act('return')}>Close</Button>
      </Box>
    );
  } else if (gameStatus === 'CLAWMACHINE_ON') {
    body = (
      <Window.Content>
        <LabeledList>
          <StatBar
            label="Progress"
            ranges={{
              bad: [-Infinity, 0],
              average: [1, 7],
              good: [8, Infinity],
            }}
            value={wintick}
            minValue={0}
            maxValue={10}
          />
        </LabeledList>
        <Box align="center">
          <br /> <hr /> <br />
          {instructions}
          <br /> <br /> <hr /> <br /> <br />
          <Button onClick={() => act('pointless')}>Up</Button>
          <br /> <br />
          <Button onClick={() => act('pointless')}>Left</Button>
          <Button onClick={() => act('pointless')}>Right</Button>
          <br /> <br />
          <Button onClick={() => act('pointless')}>Down</Button>
        </Box>
      </Window.Content>
    );
  }
  return (
    <Window>
      <Box textAlign="center">{body}</Box>
    </Window>
  );
};
