// EFTPOS scanner — TGUI.
//
// Two modes:
//   - Unlocked: configure the next transaction (purpose, value, linked
//     account) and lock it in. Also lets the owner change access code,
//     change EFTPOS ID, or reset.
//   - Locked: shows the pending charge; customer swipes ID to pay.
//     Once paid, the "Back" button needs the access code to unlock.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Data = {
  eftpos_name: string;
  machine_id: string;
  transaction_locked: BooleanLike;
  transaction_paid: BooleanLike;
  transaction_purpose: string;
  transaction_amount: number;
  linked_account_name: string;
};

export const Eftpos = () => {
  const { data, act } = useBackend<Data>();
  const {
    eftpos_name,
    machine_id,
    transaction_locked,
    transaction_paid,
    transaction_purpose,
    transaction_amount,
    linked_account_name,
  } = data;

  return (
    <Window width={520} height={420}>
      <Window.Content>
        <Section
          title={eftpos_name}
          buttons={
            transaction_locked ? (
              <Button icon="arrow-left" onClick={() => act('toggle_lock')}>
                Back{transaction_paid ? '' : ' (auth required)'}
              </Button>
            ) : null
          }
        >
          <Box italic color="label" mb={1}>
            Terminal {machine_id} — report this ID when contacting IT Support.
          </Box>

          <LabeledList>
            <LabeledList.Item label="Purpose">
              {transaction_locked ? (
                <Box inline bold>
                  {transaction_purpose}
                </Box>
              ) : (
                <Button onClick={() => act('trans_purpose')}>
                  {transaction_purpose}
                </Button>
              )}
            </LabeledList.Item>
            <LabeledList.Item label="Value">
              {transaction_locked ? (
                <Box inline bold>
                  ${transaction_amount}
                </Box>
              ) : (
                <Button onClick={() => act('trans_value')}>
                  ${transaction_amount}
                </Button>
              )}
            </LabeledList.Item>
            <LabeledList.Item label="Linked account">
              {transaction_locked ? (
                <Box inline bold>
                  {linked_account_name || 'None'}
                </Box>
              ) : (
                <Button onClick={() => act('link_account')}>
                  {linked_account_name || 'None'}
                </Button>
              )}
            </LabeledList.Item>
          </LabeledList>

          {transaction_locked ? (
            <Box mt={2}>
              {transaction_paid ? (
                <Box italic color="good">
                  This transaction has been processed successfully.
                </Box>
              ) : (
                <>
                  <Box italic color="label" mb={1}>
                    Swipe your card to finish this transaction.
                  </Box>
                  <Button fluid icon="id-card" onClick={() => act('scan_card')}>
                    [------]
                  </Button>
                </>
              )}
            </Box>
          ) : (
            <Box mt={2}>
              <Button
                fluid
                color="good"
                icon="lock"
                onClick={() => act('toggle_lock')}
              >
                Lock in new transaction
              </Button>
              <Box mt={1}>
                <Button onClick={() => act('change_code')}>
                  Change access code
                </Button>{' '}
                <Button onClick={() => act('change_id')}>
                  Change EFTPOS ID
                </Button>
              </Box>
              <Box mt={1}>
                <Box inline color="label" mr={1}>
                  Scan card to reset access code:
                </Box>
                <Button onClick={() => act('reset')}>[------]</Button>
              </Box>
            </Box>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
