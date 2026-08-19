import { useBackend } from 'tgui/backend';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type PersonalSupplyOrder = {
  ref: string;
  number: number;
  name: string;
  status: string;
  cost: number;
  reason: string;
  ordered_at: string;
  approved_by: string | null;
  can_cancel: BooleanLike;
};

type Data = {
  supply_order_account?: number;
  personal_supply_orders: PersonalSupplyOrder[];
};

const statusColor = (status: string) => {
  if (status === 'Shipped') return 'good';
  if (status === 'Denied') return 'bad';
  if (status === 'Approved') return 'average';
  return 'label';
};

export const pda_supply_orders = () => {
  const { act, data } = useBackend<Data>();
  const orders = data.personal_supply_orders ?? [];

  if (!data.supply_order_account) {
    return (
      <Box p={3} textAlign="center" color="bad">
        Insert an ID linked to the account used for your personal Cargo orders.
      </Box>
    );
  }

  if (!orders.length) {
    return (
      <Box p={3} textAlign="center" color="label">
        No personal Cargo orders are associated with this account.
      </Box>
    );
  }

  return orders.map((order) => (
    <Section
      key={order.number}
      title={`#${order.number} · ${order.name}`}
      buttons={
        !!order.can_cancel && (
          <Button
            icon="times"
            color="bad"
            onClick={() => act('cancel_personal_order', { ref: order.ref })}
          >
            Cancel and Refund
          </Button>
        )
      }
    >
      <LabeledList>
        <LabeledList.Item label="Status" color={statusColor(order.status)}>
          {order.status}
        </LabeledList.Item>
        <LabeledList.Item label="Paid">{order.cost} Thalers</LabeledList.Item>
        <LabeledList.Item label="Requested">
          {order.ordered_at}
        </LabeledList.Item>
        <LabeledList.Item label="Reason">{order.reason}</LabeledList.Item>
        {!!order.approved_by && (
          <LabeledList.Item label="Handled By">
            {order.approved_by}
          </LabeledList.Item>
        )}
      </LabeledList>
    </Section>
  ));
};
