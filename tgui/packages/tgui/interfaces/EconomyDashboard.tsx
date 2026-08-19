import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  LabeledList,
  ProgressBar,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';

type LedgerRow = { name: string; amount: number };
type DepartmentRow = {
  name: string;
  balance: number;
  savings: number;
  income: number;
  expenses: number;
  projected_payroll: number;
  last_payroll_due: number;
  last_payroll_paid: number;
};
type Data = {
  account_currency: number;
  personal_currency: number;
  personal_accounts: number;
  personal_balance_p10: number;
  personal_balance_median: number;
  personal_balance_p90: number;
  personal_zero_balance: number;
  personal_low_balance: number;
  department_savings: number;
  currency_created: number;
  currency_destroyed: number;
  currency_refunded: number;
  currency_sink_refunded: number;
  currency_internal_refunded: number;
  net_currency_flow: number;
  currency_sources: LedgerRow[];
  currency_sinks: LedgerRow[];
  projected_payroll: number;
  last_payroll_due: number;
  last_payroll_paid: number;
  unpaid_wages: number;
  allocation_policy: string;
  service_subsidies: number;
  service_invoice_count: number;
  service_sales_gross: number;
  service_sales_net: number;
  service_refund_count: number;
  service_refund_rate: number;
  service_tips: number;
  personal_orders: number;
  personal_order_spend: number;
  pending_personal_orders: number;
  market_generation: number;
  market_counterparties: number;
  market_listings: number;
  market_listing_stock: number;
  market_bids: number;
  market_target_units: number;
  market_fulfilled_units: number;
  market_purchase_volume: number;
  market_export_volume: number;
  covert_market_volume: number;
  covert_market_traces: number;
  covert_market_detections: number;
  faction_agents: number;
  agent_candidates: number;
  agent_accredited: number;
  agent_trusted: number;
  agent_operatives: number;
  agent_total_exposure: number;
  agent_contracts_completed: number;
  agent_contracts_failed: number;
  departments: DepartmentRow[];
};

const money = (value: number) => `${value.toLocaleString()} Th`;

const Ledger = (props: { rows: LedgerRow[]; empty: string }) => {
  const sorted = [...props.rows].sort((a, b) => b.amount - a.amount);
  if (!sorted.length) return <Box color="label">{props.empty}</Box>;
  return (
    <Table>
      {sorted.map((row) => (
        <Table.Row key={row.name}>
          <Table.Cell>{row.name}</Table.Cell>
          <Table.Cell textAlign="right">{money(row.amount)}</Table.Cell>
        </Table.Row>
      ))}
    </Table>
  );
};

export const EconomyDashboard = () => {
  const { data } = useBackend<Data>();
  const payrollCoverage = data.last_payroll_due
    ? data.last_payroll_paid / data.last_payroll_due
    : 1;
  return (
    <Window width={1050} height={760} title="Economy Observatory">
      <Window.Content scrollable>
        <Stack>
          <Stack.Item grow>
            <Section title="Monetary Base">
              <LabeledList>
                <LabeledList.Item label="Tracked Account Currency">
                  {money(data.account_currency)}
                </LabeledList.Item>
                <LabeledList.Item label="Personal Holdings">
                  {money(data.personal_currency)} across{' '}
                  {data.personal_accounts} accounts
                </LabeledList.Item>
                <LabeledList.Item label="Department Savings">
                  {money(data.department_savings)}
                </LabeledList.Item>
                <LabeledList.Item label="Gross Created" color="good">
                  {money(data.currency_created)}
                </LabeledList.Item>
                <LabeledList.Item label="Gross Destroyed" color="bad">
                  {money(data.currency_destroyed)}
                </LabeledList.Item>
                <LabeledList.Item label="Total Refund Activity">
                  {money(data.currency_refunded)}
                </LabeledList.Item>
                <LabeledList.Item label="External Sinks Reversed">
                  {money(data.currency_sink_refunded)}
                </LabeledList.Item>
                <LabeledList.Item label="Internal Transfers Reversed">
                  {money(data.currency_internal_refunded)}
                </LabeledList.Item>
                <LabeledList.Item
                  label="Net Ledger Flow"
                  color={data.net_currency_flow < 0 ? 'bad' : 'good'}
                >
                  {money(data.net_currency_flow)}
                </LabeledList.Item>
              </LabeledList>
            </Section>
          </Stack.Item>
          <Stack.Item grow>
            <Section title="Payroll Health">
              <LabeledList>
                <LabeledList.Item label="Allocation Policy">
                  {data.allocation_policy}
                </LabeledList.Item>
                <LabeledList.Item label="Projected Next Payroll">
                  {money(data.projected_payroll)}
                </LabeledList.Item>
                <LabeledList.Item label="Last Payroll">
                  {money(data.last_payroll_paid)} /{' '}
                  {money(data.last_payroll_due)}
                </LabeledList.Item>
                <LabeledList.Item
                  label="Unpaid Wages"
                  color={data.unpaid_wages ? 'bad' : 'good'}
                >
                  {money(data.unpaid_wages)}
                </LabeledList.Item>
              </LabeledList>
              <ProgressBar
                mt={1}
                value={payrollCoverage}
                ranges={{
                  good: [1, Infinity],
                  average: [0.75, 1],
                  bad: [-Infinity, 0.75],
                }}
              >
                {Math.round(payrollCoverage * 100)}% paid
              </ProgressBar>
            </Section>
          </Stack.Item>
          <Stack.Item grow>
            <Section title="Crew Commerce">
              <LabeledList>
                <LabeledList.Item label="Personal Cargo Orders">
                  {data.personal_orders} ({data.pending_personal_orders}{' '}
                  pending)
                </LabeledList.Item>
                <LabeledList.Item label="Personal Cargo Spend">
                  {money(data.personal_order_spend)}
                </LabeledList.Item>
                <LabeledList.Item label="Service Subsidies">
                  {money(data.service_subsidies)}
                </LabeledList.Item>
                <LabeledList.Item label="Service Sales">
                  {data.service_invoice_count} invoices ·{' '}
                  {money(data.service_sales_gross)} gross
                </LabeledList.Item>
                <LabeledList.Item label="Net Service Sales">
                  {money(data.service_sales_net)}
                </LabeledList.Item>
                <LabeledList.Item label="Refund Rate">
                  {data.service_refund_count} refunds ·{' '}
                  {Math.round(data.service_refund_rate * 100)}%
                </LabeledList.Item>
                <LabeledList.Item label="Service Tips">
                  {money(data.service_tips)}
                </LabeledList.Item>
              </LabeledList>
            </Section>
          </Stack.Item>
        </Stack>

        <Section title="Crew Liquidity Distribution" mt={1}>
          <Stack>
            <Stack.Item grow>
              <LabeledList>
                <LabeledList.Item label="10th Percentile">
                  {money(data.personal_balance_p10)}
                </LabeledList.Item>
                <LabeledList.Item label="Median Balance">
                  {money(data.personal_balance_median)}
                </LabeledList.Item>
                <LabeledList.Item label="90th Percentile">
                  {money(data.personal_balance_p90)}
                </LabeledList.Item>
              </LabeledList>
            </Stack.Item>
            <Stack.Item grow>
              <LabeledList>
                <LabeledList.Item
                  label="Below 100 Th"
                  color={data.personal_low_balance ? 'average' : 'good'}
                >
                  {data.personal_low_balance} accounts
                </LabeledList.Item>
                <LabeledList.Item
                  label="Empty Accounts"
                  color={data.personal_zero_balance ? 'bad' : 'good'}
                >
                  {data.personal_zero_balance} accounts
                </LabeledList.Item>
              </LabeledList>
            </Stack.Item>
          </Stack>
        </Section>

        <Section title="Faction Market and Agency" mt={1}>
          <Stack>
            <Stack.Item grow>
              <LabeledList>
                <LabeledList.Item label="Market Cycle">
                  #{data.market_generation} · {data.market_counterparties}{' '}
                  counterparties
                </LabeledList.Item>
                <LabeledList.Item label="Seller Inventory">
                  {data.market_listings} listings · {data.market_listing_stock}{' '}
                  available crates
                </LabeledList.Item>
                <LabeledList.Item label="Buyer Demand">
                  {data.market_bids} bids · {data.market_fulfilled_units} /{' '}
                  {data.market_target_units} units fulfilled
                </LabeledList.Item>
              </LabeledList>
            </Stack.Item>
            <Stack.Item grow>
              <LabeledList>
                <LabeledList.Item label="External Purchases">
                  {money(data.market_purchase_volume)}
                </LabeledList.Item>
                <LabeledList.Item label="Routed Exports">
                  {money(data.market_export_volume)}
                </LabeledList.Item>
                <LabeledList.Item label="Active Agents">
                  {data.faction_agents} · {data.agent_contracts_completed}{' '}
                  commissions completed · {data.agent_contracts_failed} failed
                </LabeledList.Item>
                <LabeledList.Item label="Agency Ladder">
                  {data.agent_candidates} vetting · {data.agent_accredited}{' '}
                  accredited · {data.agent_trusted} trusted ·{' '}
                  {data.agent_operatives} operative
                </LabeledList.Item>
                <LabeledList.Item label="Covert Telemetry">
                  {money(data.covert_market_volume)} ·{' '}
                  {data.covert_market_traces} traces ·{' '}
                  {data.covert_market_detections} correlated · exposure{' '}
                  {data.agent_total_exposure}
                </LabeledList.Item>
              </LabeledList>
            </Stack.Item>
          </Stack>
        </Section>

        <Stack mt={1}>
          <Stack.Item grow basis="50%">
            <Section title="Currency Sources">
              <Ledger
                rows={data.currency_sources}
                empty="No creation recorded."
              />
            </Section>
          </Stack.Item>
          <Stack.Item grow basis="50%">
            <Section title="Currency Sinks">
              <Ledger
                rows={data.currency_sinks}
                empty="No destruction recorded."
              />
            </Section>
          </Stack.Item>
        </Stack>

        <Section title="Department Solvency" mt={1}>
          <Table>
            <Table.Row header>
              <Table.Cell>Department</Table.Cell>
              <Table.Cell textAlign="right">Operating</Table.Cell>
              <Table.Cell textAlign="right">Savings</Table.Cell>
              <Table.Cell textAlign="right">Monthly Net</Table.Cell>
              <Table.Cell textAlign="right">Projected Payroll</Table.Cell>
              <Table.Cell>Last Coverage</Table.Cell>
            </Table.Row>
            {data.departments.map((department) => {
              const coverage = department.last_payroll_due
                ? department.last_payroll_paid / department.last_payroll_due
                : 1;
              return (
                <Table.Row key={department.name}>
                  <Table.Cell>{department.name}</Table.Cell>
                  <Table.Cell textAlign="right">
                    {money(department.balance)}
                  </Table.Cell>
                  <Table.Cell textAlign="right">
                    {money(department.savings)}
                  </Table.Cell>
                  <Table.Cell
                    textAlign="right"
                    color={
                      department.income < department.expenses ? 'bad' : 'good'
                    }
                  >
                    {money(department.income - department.expenses)}
                  </Table.Cell>
                  <Table.Cell textAlign="right">
                    {money(department.projected_payroll)}
                  </Table.Cell>
                  <Table.Cell>
                    <ProgressBar value={coverage}>
                      {Math.round(coverage * 100)}%
                    </ProgressBar>
                  </Table.Cell>
                </Table.Row>
              );
            })}
          </Table>
        </Section>
      </Window.Content>
    </Window>
  );
};
