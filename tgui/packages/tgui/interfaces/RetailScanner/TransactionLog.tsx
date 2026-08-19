import { Fragment } from 'react';
import { useBackend } from 'tgui/backend';
import { Button, Divider, Section, Stack, Table } from 'tgui-core/components';
import type { Data } from './types';

export const TransactionLog = (model) => {
  const { act, data } = useBackend<Data>();
  const { transaction_logs, locked, department_checkout } = data;

  return (
    <Section
      title="Transaction Log"
      fill
      scrollable
      buttons={
        !!transaction_logs.length && !department_checkout && (
          <Button.Confirm
            color="red"
            disabled={locked}
            onClick={() => act('reset_log')}
          >
            Clear Logs
          </Button.Confirm>
        )
      }
    >
      <Stack vertical>
        {transaction_logs.map((transaction) => (
          <Fragment key={transaction.log_id}>
            <Stack.Item>
              <Table>
                <Table.Row>
                  <Table.Cell colSpan={2} header>
                    {department_checkout ? 'Invoice' : 'Transaction'} #{transaction.log_id}
                  </Table.Cell>
                </Table.Row>
                <Table.Row>
                  <Table.Cell color="label">Customer</Table.Cell>
                  <Table.Cell>{transaction.customer}</Table.Cell>
                </Table.Row>
                <Table.Row>
                  <Table.Cell color="label">Pay Method</Table.Cell>
                  <Table.Cell>{transaction.payment_method}</Table.Cell>
                </Table.Row>
                <Table.Row>
                  <Table.Cell color="label">Transaction Time</Table.Cell>
                  <Table.Cell>{transaction.trans_time}</Table.Cell>
                </Table.Row>
                {!!department_checkout && (
                  <>
                    <Table.Row>
                      <Table.Cell color="label">State / Staff</Table.Cell>
                      <Table.Cell>
                        {transaction.state} · {transaction.staff}
                      </Table.Cell>
                    </Table.Row>
                    <Table.Row>
                      <Table.Cell color="label">Personal / Subsidy</Table.Cell>
                      <Table.Cell>
                        {transaction.personal} / {transaction.subsidy} Thalers
                      </Table.Cell>
                    </Table.Row>
                    <Table.Row>
                      <Table.Cell color="label">Tip (Staff / Service)</Table.Cell>
                      <Table.Cell>
                        {transaction.tip} ({transaction.staff_tip} /{' '}
                        {transaction.service_tip}) Thalers
                      </Table.Cell>
                    </Table.Row>
                    {!!transaction.refunded && (
                      <Table.Row>
                        <Table.Cell color="label">Refunded</Table.Cell>
                        <Table.Cell color="good">
                          {transaction.refund_time} by {transaction.refund_by}
                        </Table.Cell>
                      </Table.Row>
                    )}
                  </>
                )}
              </Table>
              <Divider />
              <Table>
                {Object.keys(transaction.items).map((item) => (
                  <Table.Row key={item}>
                    <Table.Cell>{`${transaction.items[item]}x ${item}`}</Table.Cell>
                    <Table.Cell collapsing>
                      {`${transaction.prices[item] * transaction.items[item]} Th`}
                    </Table.Cell>
                  </Table.Row>
                ))}
                <Table.Row>
                  <Table.Cell textAlign="right" color="label">
                    Total Amount
                  </Table.Cell>
                  <Table.Cell collapsing>{`${transaction.amount} Th`}</Table.Cell>
                </Table.Row>
              </Table>
              {!!department_checkout && !transaction.refunded && !!transaction.refundable && (
                <Button.Confirm
                  mt={1}
                  icon="undo"
                  color="bad"
                  disabled={locked}
                  onClick={() =>
                    act('refund_transaction', {
                      invoice_id: transaction.invoice_id,
                    })
                  }
                >
                  Refund Transaction
                </Button.Confirm>
              )}
              {!!department_checkout && !transaction.refunded && !transaction.refundable && (
                <Button mt={1} icon="lock" disabled>
                  Accounting Period Finalized
                </Button>
              )}
            </Stack.Item>
            <Stack.Item />
            <Stack.Divider />
          </Fragment>
        ))}
      </Stack>
    </Section>
  );
};
