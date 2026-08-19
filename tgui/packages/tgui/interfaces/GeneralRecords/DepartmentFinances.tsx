import { useBackend, useSharedState } from 'tgui/backend';
import {
  Box,
  Button,
  LabeledList,
  ProgressBar,
  Section,
  Stack,
  Table,
  Tabs,
} from 'tgui-core/components';

import type { Data, departmentFinance, financeTransaction } from './types';

const allocationAmounts = [0, 1000, 2500, 5000, 10000, 25000];
const wageMultipliers = [0.5, 0.75, 1, 1.25, 1.5, 2];
const allocationPolicies = [
  ['equal', 'Equal', 'Divide the payroll pool evenly between departments.'],
  ['staffing', 'By Staffing', 'Allocate according to active employee count.'],
  ['payroll', 'By Payroll', 'Match each department’s projected wage bill.'],
  ['manual', 'Manual', 'Use the fixed amounts configured below.'],
] as const;
const transactionsPerPage = 10;
const formatMoney = (amount: number) => `${amount.toLocaleString()} Th`;

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

const AllocationButtons = (props: {
  department: string;
  currentAllocation: number;
}) => {
  const { act } = useBackend<Data>();
  return (
    <Stack wrap>
      {allocationAmounts.map((amount) => (
        <Stack.Item key={amount}>
          <Button
            icon={amount ? 'calendar-plus' : 'ban'}
            color="good"
            selected={props.currentAllocation === amount}
            onClick={() =>
              act('set_department_allocation', {
                department: props.department,
                amount,
              })
            }
          >
            {amount ? formatMoney(amount) : 'None'}
          </Button>
        </Stack.Item>
      ))}
    </Stack>
  );
};

const DepartmentDetail = (props: {
  department: departmentFinance;
  largestBudget: number;
  canAllocate: boolean;
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
            <LabeledList.Item label="Monthly Allocation">
              {formatMoney(department.monthly_allocation)}
            </LabeledList.Item>
            <LabeledList.Item label="Income This Month" color="good">
              {formatMoney(department.monthly_income)}
            </LabeledList.Item>
            <LabeledList.Item label="Expenditure This Month" color="bad">
              {formatMoney(department.monthly_expenses)}
            </LabeledList.Item>
            <LabeledList.Item
              label="Monthly Net"
              color={monthlyNet < 0 ? 'bad' : 'good'}
            >
              {formatMoney(monthlyNet)}
            </LabeledList.Item>
            <LabeledList.Item label="Projected Payroll" color="average">
              {formatMoney(department.projected_payroll)}
            </LabeledList.Item>
            <LabeledList.Item label="Resources Before Payroll">
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
                x{multiplier}
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
                      department.service_invoices.net_billed < 0 ? 'bad' : 'good'
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
                    {formatMoney(department.service_invoices.tips)} ({
                      formatMoney(department.service_invoices.staff_tips)
                    }{' '}
                    / {formatMoney(department.service_invoices.service_tips)})
                  </LabeledList.Item>
                </LabeledList>
              </Stack.Item>
            </Stack>
          </Section>
        </>
      )}

      {canAllocate && (
        <Section mt={2} title="Monthly Station Allocation">
          <Box mb={1} color="label">
            Applied every 15 minutes. Unused operating funds roll into savings.
          </Box>
          <AllocationButtons
            department={department.department}
            currentAllocation={department.monthly_allocation}
          />
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
        <Section title="Station Budget Allocation">
          <Stack mb={2}>
            <Stack.Item grow>
              <Box color="label">Unallocated Station Funds</Box>
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
          <Section title="Station Monthly Cash Flow" mb={2}>
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
                  <Box color="label">No income recorded this month.</Box>
                )}
              </Stack.Item>
            </Stack>
          </Section>
          <Section title="Automatic Allocation Policy" mb={2}>
            <Box color="label" mb={1}>
              Automatic policies divide the projected station payroll pool.
              Selecting a fixed department amount switches the station to
              Manual.
            </Box>
            <Stack wrap>
              {allocationPolicies.map(([policy, label, description]) => (
                <Stack.Item key={policy}>
                  <Button
                    selected={allocation_policy === policy}
                    tooltip={description}
                    onClick={() => act('set_allocation_policy', { policy })}
                  >
                    {label}
                  </Button>
                </Stack.Item>
              ))}
            </Stack>
          </Section>
          {department_finances.length ? (
            <Table>
              <Table.Row header>
                <Table.Cell>Department</Table.Cell>
                <Table.Cell>Funds</Table.Cell>
                <Table.Cell textAlign="right">Savings</Table.Cell>
                <Table.Cell>Monthly Allocation</Table.Cell>
              </Table.Row>
              {department_finances.map((department) => (
                <Table.Row key={department.department}>
                  <Table.Cell>
                    <Button
                      color="transparent"
                      onClick={() => setRequestedTab(department.department)}
                    >
                      {department.department}
                    </Button>
                  </Table.Cell>
                  <Table.Cell>
                    <ProgressBar
                      value={(department.balance + department.savings) / largestBudget}
                      ranges={{
                        good: [0.5, Infinity],
                        average: [0.2, 0.5],
                        bad: [-Infinity, 0.2],
                      }}
                    />
                  </Table.Cell>
                  <Table.Cell textAlign="right">
                    {formatMoney(department.savings)}
                  </Table.Cell>
                  <Table.Cell>
                    <Box mb={1} color="label">
                      Current: {formatMoney(department.monthly_allocation)}
                    </Box>
                    <AllocationButtons
                      department={department.department}
                      currentAllocation={department.monthly_allocation}
                    />
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
      )}

      {!!selectedDepartment && (
        <DepartmentDetail
          department={selectedDepartment}
          largestBudget={largestBudget}
          canAllocate={canAllocate}
        />
      )}
    </Box>
  );
};
