import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  NoticeBox,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import type {
  SecureSafeActions,
  SecureSafeData,
} from './generated/SecureSafe';

const NukeKeypad = (props) => {
  const { act, data } = useBackend<SecureSafeData, SecureSafeActions>();

  const keypadKeys: string[][] = [
    ['1', '4', '7', 'R'],
    ['2', '5', '8', '0'],
    ['3', '6', '9', 'E'],
  ];

  const { locked, l_setshort, code, emagged } = data;
  return (
    <Box width="185px">
      <Table width="1px">
        <Table.Row>
          {keypadKeys.map((keyColumn) => (
            <Table.Cell key={keyColumn[0]}>
              {keyColumn.map((key) => (
                <Button
                  fluid
                  bold
                  key={key}
                  mb="6px"
                  textAlign="center"
                  fontSize="40px"
                  height="50px"
                  lineHeight={1.25}
                  disabled={
                    !!emagged ||
                    (!!l_setshort && 1) ||
                    (key !== 'R' && !locked) ||
                    (code === 'ERROR' && key !== 'R' && 1)
                  }
                  onClick={() => act('type', { digit: key })}
                >
                  {key}
                </Button>
              ))}
            </Table.Cell>
          ))}
        </Table.Row>
      </Table>
    </Box>
  );
};

export const SecureSafe = (props) => {
  const { act, data } = useBackend<SecureSafeData, SecureSafeActions>();
  const { code, l_setshort, l_set, emagged, locked } = data;

  const new_code: boolean = !(!!l_set || !!l_setshort);

  return (
    <Window width={250} height={380}>
      <Window.Content>
        <Box m="6px">
          {new_code && (
            <NoticeBox textAlign="center" info>
              ENTER NEW 5-DIGIT PASSCODE.
            </NoticeBox>
          )}
          {!!emagged && (
            <NoticeBox textAlign="center" danger>
              LOCKING SYSTEM ERROR - 1701
            </NoticeBox>
          )}
          {!!l_setshort && (
            <NoticeBox textAlign="center" danger>
              ALERT: MEMORY SYSTEM ERROR - 6040 201
            </NoticeBox>
          )}
          <Section height="60px">
            <Box textAlign="center" position="center" fontSize="35px">
              {(code && code) || (
                <Box textColor={locked ? 'red' : 'green'}>
                  {locked ? 'LOCKED' : 'UNLOCKED'}
                </Box>
              )}
            </Box>
          </Section>
          <Stack ml="3px">
            <Stack.Item>
              <NukeKeypad />
            </Stack.Item>
            <Stack.Item ml="6px" width="129px" />
          </Stack>
        </Box>
      </Window.Content>
    </Window>
  );
};
