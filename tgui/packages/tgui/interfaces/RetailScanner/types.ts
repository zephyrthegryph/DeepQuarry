import type { BooleanLike } from 'tgui-core/react';

export type Data = {
  locked: BooleanLike;
  cash_locked?: BooleanLike;
  linked_account: string | null;
  machine_id: string;
  department_checkout: BooleanLike;
  subsidized_checkout: BooleanLike;
  transaction_logs: {
    invoice_id?: number;
    log_id: number;
    customer: string;
    payment_method: string;
    trans_time: string;
    items: Record<string, number>;
    prices: Record<string, number>;
    amount: number;
    subsidy: number;
    personal: number;
    refunded: BooleanLike;
    refundable: BooleanLike;
    refund_time: string | null;
    refund_by: string | null;
    state?: string;
    staff?: string;
    tip?: number;
    staff_tip?: number;
    service_tip?: number;
  }[];
  current_transactioon: {
    items?: Record<string, number>;
    prices?: Record<string, number>;
    amount?: number;
  };
};
