import { useBackend, useSharedState } from 'tgui/backend';
import {
  Box,
  Button,
  LabeledList,
  NumberInput,
  ProgressBar,
  Section,
  Stack,
  Table,
  Tabs,
} from 'tgui-core/components';

import type { Data, departmentFinance, financeTransaction } from './types';

const wageMultipliers = [0.5, 0.75, 1, 1.25, 1.5, 2];
const transferPresets = [250, 500, 1000, 2500, 5000];
const allocationPolicies = [
  [
    'equal',
    'Equal Shares',
    'Divide recurring operating funds equally. Payroll remains separate and takes priority.',
  ],
  [
    'staffing',
    'By Staffing',
    'Divide recurring operating funds according to active staff. Payroll remains separate.',
  ],
  [
    'payroll',
    'No Operating Pool',
    'Fund payroll without recurring discretionary allocations.',
  ],
] as const;
const transactionsPerPage = 10;
const formatMoney = (amount: number) => `${amount.toLocaleString()} Th`;

const departmentColors: Record<string, string> = {
  Command: '#d7b447',
  Security: '#c94f55',
  Engineering: '#df8f3c',
  Medical: '#4eb6c2',
  Research: '#9b6ac9',
  Cargo: '#a9794f',
  Civilian: '#66a86d',
  Exploration: '#4b91a8',
};

type BudgetSlice = {
  label: string;
  amount: number;
  color: string;
};

const DonutRing = (props: {
  slices: BudgetSlice[];
  total: number;
  radius: number;
  width: number;
}) => {
  const circumference = 2 * Math.PI * props.radius;
  let offset = 0;
  return (
    <>
      <circle
        cx="120"
        cy="120"
        r={props.radius}
        fill="none"
        stroke="#20252b"
        strokeWidth={props.width}
      />
      {props.slices.map((slice) => {
        const fraction = Math.max(0, slice.amount) / Math.max(1, props.total);
        const length = Math.min(circumference, circumference * fraction);
        const dashOffset = -offset;
        offset += length;
        return (
          <circle
            key={slice.label}
            cx="120"
            cy="120"
            r={props.radius}
            fill="none"
            stroke={slice.color}
            strokeWidth={props.width}
            strokeDasharray={`${length} ${circumference - length}`}
            strokeDashoffset={dashOffset}
            strokeLinecap="butt"
            transform="rotate(-90 120 120)"
          >
            <title>
              {slice.label}: {formatMoney(slice.amount)}
            </title>
          </circle>
        );
      })}
    </>
  );
};

const BudgetChart = (props: {
  plan: NonNullable<Data['budget_plan']>;
  departments: departmentFinance[];
  nextCycle: string | null;
}) => {
  const { plan, departments } = props;
  const innerSlices: BudgetSlice[] = [
    { label: 'Staff payroll', amount: plan.payroll_funded, color: '#4b8fcc' },
    {
      label: 'Department operations',
      amount: plan.operating_funded,
      color: '#55a96b',
    },
    { label: 'Station reserve', amount: plan.remaining, color: '#69737d' },
  ];
  const outerSlices: BudgetSlice[] = departments
    .filter((department) => department.operating_allocation > 0)
    .map((department) => ({
      label: department.department,
      amount: department.operating_allocation,
      color: departmentColors[department.department] || '#8793a1',
    }));
  if (plan.unallocated_operating > 0) {
    outerSlices.push({
      label: 'Unassigned operating reserve',
      amount: plan.unallocated_operating,
      color: '#424a52',
    });
  }
  return (
    <Stack align="center">
      <Stack.Item basis="280px">
        <Box textAlign="center">
          <svg width="240" height="240" viewBox="0 0 240 240">
            <DonutRing
              slices={innerSlices}
              total={plan.available}
              radius={69}
              width={30}
            />
            <DonutRing
              slices={outerSlices}
              total={plan.operating_pool}
              radius={101}
              width={12}
            />
            <text
              x="120"
              y="108"
              textAnchor="middle"
              fill="#aeb8c2"
              fontSize="11"
            >
              AVAILABLE
            </text>
            <text
              x="120"
              y="130"
              textAnchor="middle"
              fill="#ffffff"
              fontSize="17"
              fontWeight="bold"
            >
              {plan.available.toLocaleString()} Th
            </text>
            <text
              x="120"
              y="147"
              textAnchor="middle"
              fill="#8e9aa5"
              fontSize="10"
            >
              in {props.nextCycle || '—'}
            </text>
          </svg>
        </Box>
        <Box textAlign="center" color="label" fontSize="11px">
          Inner: funding waterfall · Outer: operating split
        </Box>
      </Stack.Item>
      <Stack.Item grow>
        <LabeledList>
          <LabeledList.Item label="Funds on hand">
            {formatMoney(plan.available - plan.nt_grant)}
          </LabeledList.Item>
          <LabeledList.Item label="NT payroll support" color="good">
            +{formatMoney(plan.nt_grant)}
          </LabeledList.Item>
          <LabeledList.Item
            label="1 · Staff payroll"
            color={
              plan.payroll_funded < plan.projected_payroll ? 'bad' : 'good'
            }
          >
            −{formatMoney(plan.payroll_funded)} /{' '}
            {formatMoney(plan.projected_payroll)} due
          </LabeledList.Item>
          <LabeledList.Item
            label="2 · Department operations"
            color={
              plan.operating_funded < plan.operating_requested ? 'bad' : 'good'
            }
          >
            −{formatMoney(plan.operating_funded)} /{' '}
            {formatMoney(plan.operating_requested)} assigned
          </LabeledList.Item>
          <LabeledList.Item label="3 · Station reserve" color="label">
            {formatMoney(plan.remaining)} retained
          </LabeledList.Item>
        </LabeledList>
        {!!plan.shortfall && (
          <Box
            mt={1}
            p={1}
            color="bad"
            backgroundColor="rgba(150, 35, 45, 0.2)"
          >
            Funding shortfall: {formatMoney(plan.shortfall)}. Payroll is funded
            before department operations.
          </Box>
        )}
      </Stack.Item>
    </Stack>
  );
};

const TransactionTable = (props: {
  transactions: financeTransaction[];
  pageKey: string;
}) => {
  const [requestedPage, setRequestedPage] = useSharedState(
    `financeTransactionsPage-${props.pageKey}`,
    1,
  );
  if (!props.transactions.length) {
    return <Box color="label">No transactions have been recorded.</Box>;
  }
  const pageCount = Math.ceil(props.transactions.length / transactionsPerPage);
  const page = Math.min(Math.max(requestedPage, 1), pageCount);
  const transactions = props.transactions.slice(
    (page - 1) * transactionsPerPage,
    page * transactionsPerPage,
  );
  return (
    <>
      <Table>
        <Table.Row header>
          <Table.Cell>Time</Table.Cell>
          <Table.Cell>Purpose</Table.Cell>
          <Table.Cell>Counterparty</Table.Cell>
          <Table.Cell>Terminal</Table.Cell>
          <Table.Cell textAlign="right">Amount</Table.Cell>
        </Table.Row>
        {transactions.map((transaction, index) => (
          <Table.Row key={`${transaction.date}-${transaction.time}-${index}`}>
            <Table.Cell collapsing>
              {transaction.date} {transaction.time}
            </Table.Cell>
            <Table.Cell>{transaction.purpose}</Table.Cell>
            <Table.Cell>{transaction.target}</Table.Cell>
            <Table.Cell>{transaction.terminal}</Table.Cell>
            <Table.Cell textAlign="right">{transaction.amount} Th</Table.Cell>
          </Table.Row>
        ))}
      </Table>
      {pageCount > 1 && (
        <Stack mt={1} justify="center" align="center">
          <Stack.Item>
            <Button
              icon="chevron-left"
              disabled={page <= 1}
              onClick={() => setRequestedPage(page - 1)}
            />
          </Stack.Item>
          <Stack.Item color="label">
            Page {page} of {pageCount}
          </Stack.Item>
          <Stack.Item>
            <Button
              icon="chevron-right"
              disabled={page >= pageCount}
              onClick={() => setRequestedPage(page + 1)}
            />
          </Stack.Item>
        </Stack>
      )}
    </>
  );
};

const AllocationControl = (props: {
  department: departmentFinance;
  showAmount?: boolean;
}) => {
  const { act } = useBackend<Data>();
  const { department } = props;
  return (
    <Stack align="center">
      <Stack.Item>
        <NumberInput
          value={department.allocation_percent}
          minValue={0}
          maxValue={100}
          step={1}
          unit="%"
          width="80px"
          onChange={(percent) =>
            act('set_department_allocation_percent', {
              department: department.department,
              percent,
            })
          }
        />
      </Stack.Item>
      <Stack.Item>
        <Button
          icon="rotate-left"
          disabled={!department.allocation_overridden}
          tooltip="Return this department to the selected automatic policy."
          onClick={() =>
            act('clear_department_allocation', {
              department: department.department,
            })
          }
        >
          Automatic
        </Button>
      </Stack.Item>
      <Stack.Item color={department.allocation_overridden ? 'average' : 'good'}>
        {department.allocation_overridden ? 'Override' : 'Policy'}
      </Stack.Item>
      {props.showAmount !== false && (
        <Stack.Item color="label">
          {formatMoney(department.operating_allocation)} operating
        </Stack.Item>
      )}
    </Stack>
  );
};

const OneTimeTransfer = (props: { department: string }) => {
  const { act } = useBackend<Data>();
  const [amount, setAmount] = useSharedState(
    `oneTimeFunding-${props.department}`,
    1000,
  );
  return (
    <Stack align="center" wrap>
      <Stack.Item basis="100%">
        <Stack align="center" wrap>
          {transferPresets.map((preset) => (
            <Stack.Item key={preset}>
              <Button
                selected={amount === preset}
                onClick={() => setAmount(preset)}
              >
                {preset.toLocaleString()} Th
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      </Stack.Item>
      <Stack.Item mt={1}>
        <NumberInput
          value={amount}
          minValue={1}
          maxValue={1000000}
          step={250}
          unit=" Th"
          width="110px"
          onChange={setAmount}
        />
      </Stack.Item>
      <Stack.Item mt={1}>
        <Button
          icon="money-bill-transfer"
          color="good"
          onClick={() =>
            act('transfer_department_funds', {
              department: props.department,
              amount,
            })
          }
        >
          Transfer Now
        </Button>
      </Stack.Item>
    </Stack>
  );
};

const DepartmentDetail = (props: {
  department: departmentFinance;
  largestBudget: number;
  canAllocate: boolean;
  nextCycle: string | null;
}) => {
  const { act } = useBackend<Data>();
  const { department, largestBudget, canAllocate } = props;
  const monthlyNet = department.monthly_income - department.monthly_expenses;
  return (
    <Section title={`${department.department} Financial Overview`}>
      <Stack>
        <Stack.Item grow basis="48%">
          <Box color="label">Operating Funds</Box>
          <Box bold fontSize="24px" color="good">
            {formatMoney(department.balance)}
          </Box>
          <ProgressBar
            mt={1}
            value={department.balance / largestBudget}
            ranges={{
              good: [0.5, Infinity],
              average: [0.2, 0.5],
              bad: [-Infinity, 0.2],
            }}
          />
        </Stack.Item>
        <Stack.Item grow>
          <LabeledList>
            <LabeledList.Item label="Savings" color="good">
              {formatMoney(department.savings)}
            </LabeledList.Item>
            <LabeledList.Item label="Next Allocation">
              {formatMoney(department.monthly_allocation)}
            </LabeledList.Item>
            <LabeledList.Item label="Expected Funding">
              {formatMoney(department.funded_allocation)}
            </LabeledList.Item>
            <LabeledList.Item
              label="Allocation Shortfall"
              color={department.allocation_shortfall ? 'bad' : 'good'}
            >
              {formatMoney(department.allocation_shortfall)}
            </LabeledList.Item>
            <LabeledList.Item label="Income This Period" color="good">
              {formatMoney(department.monthly_income)}
            </LabeledList.Item>
            <LabeledList.Item label="Spending This Period" color="bad">
              {formatMoney(department.monthly_expenses)}
            </LabeledList.Item>
            <LabeledList.Item
              label="Period Net"
              color={monthlyNet < 0 ? 'bad' : 'good'}
            >
              {formatMoney(monthlyNet)}
            </LabeledList.Item>
            <LabeledList.Item label="Active Employees">
              {department.employee_count}
            </LabeledList.Item>
            <LabeledList.Item label="Projected Payroll" color="average">
              {formatMoney(department.projected_payroll)}
            </LabeledList.Item>
            <LabeledList.Item label="Projected Payroll Resources">
              {formatMoney(department.payroll_resources)}
            </LabeledList.Item>
            <LabeledList.Item
              label="Expected Payroll Coverage"
              color={department.payroll_coverage < 1 ? 'bad' : 'good'}
            >
              {Math.round(department.payroll_coverage * 100)}%
            </LabeledList.Item>
            <LabeledList.Item label="Last Payroll">
              {formatMoney(department.last_payroll_paid)} /{' '}
              {formatMoney(department.last_payroll_due)}
            </LabeledList.Item>
            <LabeledList.Item
              label="Last Shortfall"
              color={department.last_payroll_shortfall ? 'bad' : 'good'}
            >
              {formatMoney(department.last_payroll_shortfall)}
            </LabeledList.Item>
            <LabeledList.Item label="Department Wage Rate">
              x{department.wage_multiplier}
            </LabeledList.Item>
          </LabeledList>
        </Stack.Item>
      </Stack>

      <Section mt={2} title="Department Wage Policy">
        <Box color="label" mb={1}>
          Percentage of each job’s base wage paid every 15-minute pay period.
        </Box>
        <Stack wrap>
          {wageMultipliers.map((multiplier) => (
            <Stack.Item key={multiplier}>
              <Button
                selected={department.wage_multiplier === multiplier}
                onClick={() =>
                  act('set_department_wages', {
                    department: department.department,
                    multiplier,
                  })
                }
              >
                {Math.round(multiplier * 100)}%
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      </Section>

      {department.department === 'Civilian' && (
        <>
          <Section mt={2} title="Service Checkout Policy">
            <Box color="label" mb={1}>
              This subsidy applies to customers above the automatic low-income
              threshold. Customers always see the resulting quote before paying.
            </Box>
            <Stack wrap>
              {[0, 0.25, 0.5, 0.75, 1].map((subsidy) => (
                <Stack.Item key={subsidy}>
                  <Button
                    selected={department.service_subsidy === subsidy}
                    onClick={() => act('set_service_subsidy', { subsidy })}
                  >
                    {Math.round(subsidy * 100)}% subsidy
                  </Button>
                </Stack.Item>
              ))}
            </Stack>
          </Section>
          <Section mt={2} title="Service Invoices · Current Accounting Period">
            <Stack>
              <Stack.Item grow>
                <LabeledList>
                  <LabeledList.Item label="Invoices">
                    {department.service_invoices.invoice_count}
                  </LabeledList.Item>
                  <LabeledList.Item label="Gross Billed" color="good">
                    {formatMoney(department.service_invoices.gross_billed)}
                  </LabeledList.Item>
                  <LabeledList.Item label="Refunds" color="bad">
                    {department.service_invoices.refund_count} ·{' '}
                    {formatMoney(department.service_invoices.refunded_total)}
                  </LabeledList.Item>
                  <LabeledList.Item
                    label="Net Billed"
                    color={
                      department.service_invoices.net_billed < 0
                        ? 'bad'
                        : 'good'
                    }
                  >
                    {formatMoney(department.service_invoices.net_billed)}
                  </LabeledList.Item>
                </LabeledList>
              </Stack.Item>
              <Stack.Item grow>
                <LabeledList>
                  <LabeledList.Item label="ID Accounts">
                    {formatMoney(department.service_invoices.account_sales)}
                  </LabeledList.Item>
                  <LabeledList.Item label="Cash">
                    {formatMoney(department.service_invoices.cash_sales)}
                  </LabeledList.Item>
                  <LabeledList.Item label="E-Wallet">
                    {formatMoney(department.service_invoices.ewallet_sales)}
                  </LabeledList.Item>
                  <LabeledList.Item label="Tips (Staff / Service)">
                    {formatMoney(department.service_invoices.tips)} (
                    {formatMoney(department.service_invoices.staff_tips)} /{' '}
                    {formatMoney(department.service_invoices.service_tips)})
                  </LabeledList.Item>
                </LabeledList>
              </Stack.Item>
            </Stack>
          </Section>
        </>
      )}

      {canAllocate && (
        <>
          <Section mt={2} title="Recurring Operating Share">
            <Box mb={1} color="label">
              This percentage divides the station operating pool every pay
              period. Payroll is calculated separately and funded first. Next
              settlement: {props.nextCycle || '—'}.
            </Box>
            <AllocationControl department={department} />
          </Section>
          <Section mt={2} title="One-Time Funding">
            <Box mb={1} color="label">
              Transfer station funds immediately. This does not alter future
              allocations or wages.
            </Box>
            <OneTimeTransfer department={department.department} />
          </Section>
        </>
      )}

      {!!department.income_sources.length && (
        <Section mt={2} title="Income Sources · Current Period">
          <Table>
            {department.income_sources.map((source) => (
              <Table.Row key={source.source}>
                <Table.Cell>{source.source}</Table.Cell>
                <Table.Cell textAlign="right" color="good">
                  {formatMoney(source.amount)}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
      )}

      <Section mt={2} title="Recent Transactions">
        <TransactionTable
          transactions={department.transactions}
          pageKey={department.department}
        />
      </Section>
    </Section>
  );
};

export const DepartmentFinances = (props) => {
  const { act, data } = useBackend<Data>();
  const {
    can_allocate_station_budget,
    department_finances = [],
    station_balance,
    station_income_sources = [],
    station_monthly_expenses,
    station_monthly_income,
    nt_salary_support,
    allocation_policy,
    next_budget_cycle,
    budget_plan,
    station_transactions = [],
  } = data;
  const canAllocate = !!can_allocate_station_budget;
  const defaultTab = canAllocate
    ? 'overview'
    : department_finances[0]?.department || 'overview';
  const [requestedTab, setRequestedTab] = useSharedState(
    'departmentFinanceTab',
    defaultTab,
  );
  const validTabs = [
    ...(canAllocate ? ['overview'] : []),
    ...department_finances.map((department) => department.department),
  ];
  const selectedTab = validTabs.includes(requestedTab)
    ? requestedTab
    : defaultTab;
  const selectedDepartment = department_finances.find(
    (department) => department.department === selectedTab,
  );
  const totalDepartmentFunds = department_finances.reduce(
    (sum, department) => sum + department.balance + department.savings,
    0,
  );
  const largestBudget = Math.max(
    1,
    ...department_finances.map(
      (department) => department.balance + department.savings,
    ),
  );
  const stationMonthlyNet =
    (station_monthly_income || 0) - (station_monthly_expenses || 0);
  const hasCustomAllocation = department_finances.some(
    (department) => !!department.allocation_overridden,
  );

  return (
    <Box>
      <Tabs>
        {canAllocate && (
          <Tabs.Tab
            icon="chart-pie"
            selected={selectedTab === 'overview'}
            onClick={() => setRequestedTab('overview')}
          >
            Allocation
          </Tabs.Tab>
        )}
        {department_finances.map((department) => (
          <Tabs.Tab
            key={department.department}
            selected={selectedTab === department.department}
            onClick={() => setRequestedTab(department.department)}
          >
            {department.department}
          </Tabs.Tab>
        ))}
      </Tabs>

      {selectedTab === 'overview' && canAllocate && (
        <Section
          title="Next Pay-Period Plan"
          buttons={
            <Button icon="refresh" onClick={() => act('refresh')}>
              Refresh
            </Button>
          }
        >
          <Stack mb={2}>
            <Stack.Item grow>
              <Box color="label">Current Station Funds</Box>
              <Box bold fontSize="24px" color="good">
                {formatMoney(station_balance || 0)}
              </Box>
            </Stack.Item>
            <Stack.Item grow>
              <Box color="label">Department Operating + Savings</Box>
              <Box bold fontSize="24px">
                {formatMoney(totalDepartmentFunds)}
              </Box>
            </Stack.Item>
          </Stack>
          {!!budget_plan && (
            <Section title="Funding Waterfall" mb={2}>
              <BudgetChart
                plan={budget_plan}
                departments={department_finances}
                nextCycle={next_budget_cycle}
              />
            </Section>
          )}
          <Section title="Current Pay-Period Cash Flow" mb={2}>
            <Stack>
              <Stack.Item grow>
                <LabeledList>
                  <LabeledList.Item label="Income" color="good">
                    {formatMoney(station_monthly_income || 0)}
                  </LabeledList.Item>
                  <LabeledList.Item label="Expenditure" color="bad">
                    {formatMoney(station_monthly_expenses || 0)}
                  </LabeledList.Item>
                  <LabeledList.Item
                    label="Net"
                    color={stationMonthlyNet < 0 ? 'bad' : 'good'}
                  >
                    {formatMoney(stationMonthlyNet)}
                  </LabeledList.Item>
                  <LabeledList.Item label="NT Payroll Support">
                    {Math.round((nt_salary_support || 0) * 100)}% of projected
                    payroll
                  </LabeledList.Item>
                </LabeledList>
              </Stack.Item>
              <Stack.Item grow>
                <Box bold mb={1}>
                  Income Sources
                </Box>
                {station_income_sources.length ? (
                  <Table>
                    {station_income_sources.map((source) => (
                      <Table.Row key={source.source}>
                        <Table.Cell>{source.source}</Table.Cell>
                        <Table.Cell textAlign="right" color="good">
                          {formatMoney(source.amount)}
                        </Table.Cell>
                      </Table.Row>
                    ))}
                  </Table>
                ) : (
                  <Box color="label">No income recorded this period.</Box>
                )}
              </Stack.Item>
            </Stack>
          </Section>
          <Section
            title="Recurring Operating Plan"
            mb={2}
            buttons={
              <Box color="label">
                {Math.max(
                  0,
                  100 -
                    department_finances.reduce(
                      (sum, department) => sum + department.allocation_percent,
                      0,
                    ),
                ).toFixed(1)}
                % unassigned
              </Box>
            }
          >
            <Box color="label" mb={1}>
              First, payroll is funded from available station money. Then each
              department receives its share of the operating pool. Any
              unassigned share and all money left afterward remain in the
              station reserve.
            </Box>
            <Stack align="center" mb={1} wrap>
              <Stack.Item color="label">Presets</Stack.Item>
              {allocationPolicies.map(([policy, label, description]) => (
                <Stack.Item key={policy}>
                  <Button
                    selected={
                      allocation_policy === policy && !hasCustomAllocation
                    }
                    tooltip={description}
                    onClick={() => act('set_allocation_policy', { policy })}
                  >
                    {label}
                  </Button>
                </Stack.Item>
              ))}
              {hasCustomAllocation && (
                <Stack.Item color="average">Custom plan</Stack.Item>
              )}
            </Stack>
            {department_finances.length ? (
              <Table>
                <Table.Row header>
                  <Table.Cell>Department</Table.Cell>
                  <Table.Cell textAlign="center">Staff</Table.Cell>
                  <Table.Cell textAlign="right">Payroll</Table.Cell>
                  <Table.Cell>Operating share</Table.Cell>
                  <Table.Cell textAlign="right">Expected</Table.Cell>
                </Table.Row>
                {department_finances.map((department) => (
                  <Table.Row key={department.department}>
                    <Table.Cell>
                      <Button
                        color="transparent"
                        onClick={() => setRequestedTab(department.department)}
                      >
                        <Box
                          inline
                          mr={0.5}
                          width="8px"
                          height="8px"
                          backgroundColor={
                            departmentColors[department.department] || '#8793a1'
                          }
                        />
                        {department.department}
                      </Button>
                    </Table.Cell>
                    <Table.Cell textAlign="center">
                      {department.employee_count}
                    </Table.Cell>
                    <Table.Cell textAlign="right">
                      {formatMoney(department.projected_payroll)}
                    </Table.Cell>
                    <Table.Cell>
                      <AllocationControl
                        department={department}
                        showAmount={false}
                      />
                    </Table.Cell>
                    <Table.Cell textAlign="right">
                      {formatMoney(department.operating_allocation)}
                    </Table.Cell>
                  </Table.Row>
                ))}
              </Table>
            ) : (
              <Box color="bad">
                No departmental accounts are available to this ID.
              </Box>
            )}
          </Section>
          {!!station_transactions.length && (
            <Section mt={2} title="Station Transactions">
              <TransactionTable
                transactions={station_transactions}
                pageKey="station"
              />
            </Section>
          )}
        </Section>
      )}

      {!!selectedDepartment && (
        <DepartmentDetail
          department={selectedDepartment}
          largestBudget={largestBudget}
          canAllocate={canAllocate}
          nextCycle={next_budget_cycle}
        />
      )}
    </Box>
  );
};
