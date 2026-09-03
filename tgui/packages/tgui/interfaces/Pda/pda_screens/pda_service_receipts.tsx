import { useBackend } from 'tgui/backend';
import { Box, LabeledList, Section, Table } from 'tgui-core/components';

type ServiceReceipt = {
  invoice_id: number;
  state: string;
  customer: string;
  trans_time: string;
  trans_date: string;
  terminal: string;
  staff: string;
  items: Record<string, number>;
  prices: Record<string, number>;
  amount: number;
  subsidy: number;
  personal: number;
  tip: number;
};

type Data = {
  service_receipt_account?: number;
  service_receipts: ServiceReceipt[];
};

export const pda_service_receipts = () => {
  const { data } = useBackend<Data>();
  const receipts = data.service_receipts ?? [];

  if (!data.service_receipt_account) {
    return (
      <Box p={3} textAlign="center" color="bad">
        Insert an ID linked to your account to view Service receipts.
      </Box>
    );
  }

  if (!receipts.length) {
    return (
      <Box p={3} textAlign="center" color="label">
        No Service invoices are associated with this account.
      </Box>
    );
  }

  return receipts.map((receipt) => (
    <Section
      key={receipt.invoice_id}
      title={`Invoice #${receipt.invoice_id} · ${receipt.state}`}
    >
      <LabeledList>
        <LabeledList.Item label="Date">
          {receipt.trans_date} {receipt.trans_time}
        </LabeledList.Item>
        <LabeledList.Item label="Terminal">{receipt.terminal}</LabeledList.Item>
        <LabeledList.Item label="Served By">{receipt.staff}</LabeledList.Item>
        <LabeledList.Item label="Personal / Subsidy">
          {receipt.personal} / {receipt.subsidy} Thalers
        </LabeledList.Item>
        <LabeledList.Item label="Tip">{receipt.tip} Thalers</LabeledList.Item>
      </LabeledList>
      <Table mt={1}>
        {Object.entries(receipt.items).map(([item, quantity]) => (
          <Table.Row key={item}>
            <Table.Cell>
              {quantity}x {item}
            </Table.Cell>
            <Table.Cell textAlign="right">
              {quantity * receipt.prices[item]} Th
            </Table.Cell>
          </Table.Row>
        ))}
        <Table.Row>
          <Table.Cell bold>Total</Table.Cell>
          <Table.Cell bold textAlign="right">
            {receipt.amount} Th
          </Table.Cell>
        </Table.Row>
      </Table>
    </Section>
  ));
};
