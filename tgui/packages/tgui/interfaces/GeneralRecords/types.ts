import type { BooleanLike } from 'tgui-core/react';

export type Data = {
  temp: { color: string; text: string } | null;
  scan: string | null;
  authenticated: BooleanLike;
  rank: string | null;
  screen: number | null;
  printing: BooleanLike;
  isAI: BooleanLike;
  isRobot: BooleanLike;
  can_allocate_station_budget: BooleanLike;
  station_balance: number | null;
  station_monthly_income: number | null;
  station_monthly_expenses: number | null;
  station_income_sources: financeIncomeSource[];
  nt_salary_support: number | null;
  allocation_policy: string | null;
  next_budget_cycle: string | null;
  budget_plan: budgetPlan | null;
  department_finances: departmentFinance[];
  contract_departments: string[];
  contract_faction_standings: factionStanding[];
  station_transactions: financeTransaction[];
  contracts: managementContract[];
  records: record[] | undefined;
  general:
    | {
        fields: field[] | undefined;
        photos: string[] | undefined;
        has_photos: BooleanLike;
        skills: string[] | undefined;
        comments: { header: string; text: string }[] | undefined;
        empty: BooleanLike;
      }
    | undefined;
};

export type factionStanding = {
  name: string;
  acronym: string;
  color: string;
  tier: string;
  department_tiers: Record<string, string>;
};

export type contractRequirement = {
  name: string;
  description: string;
  state: string;
  required: boolean;
  progress: number;
  target: number;
  progress_text: string;
  stages: contractRequirementStage[];
};

export type contractRequirementStage = {
  index: number;
  label: string;
  threshold: number;
  unit: string;
  duration: string;
  status: string;
};

export type managementContract = {
  id: string;
  title: string;
  description: string;
  scope: string;
  state: string;
  issuer: string;
  issuer_faction: string;
  issuer_acronym: string;
  issuer_color: string;
  department?: string;
  reward: number;
  paid_reward: number;
  standing_score: number;
  standing_tier: string;
  standing_reward_modifier: number;
  term_class: string;
  reward_distribution: contractDistribution;
  reputation_distribution: contractDistribution;
  secondary_reputation: factionReputationChange[];
  negotiation_locked: BooleanLike;
  negotiation_clauses: contractNegotiationClause[];
  can_accept: boolean;
  can_decline: boolean;
  offer_kind: string;
  closure_code?: string;
  offer_time_remaining?: string;
  deadline_remaining?: string;
  grace_time_remaining?: string;
  requirements: contractRequirement[];
  details?:
    | medicalTrialDetails
    | medicalCaseReportDetails
    | socialOutcomeDetails;
};

export type contractDistribution = {
  station: number;
  department: number;
  staff: number;
};

export type contractClauseOption = {
  id: string;
  title: string;
  description: string;
  station_money: number;
  department_money: number;
  staff_money: number;
  station_reputation: number;
  department_reputation: number;
  staff_reputation: number;
  deadline_minutes: number;
  other_reputation: factionReputationChange[];
};

export type factionReputationChange = {
  faction: string;
  acronym: string;
  color: string;
  amount: number;
};

export type contractNegotiationClause = {
  id: string;
  title: string;
  description: string;
  selected: string;
  options: contractClauseOption[];
};

export type medicalTrialSubject = {
  name: string;
  subject_ref: string;
  cohort_class: string;
  status: string;
  next_step: string;
  marker_detected: BooleanLike;
  can_reissue: BooleanLike;
  can_revoke: BooleanLike;
};

export type medicalTrialDetails = {
  kind: 'medical_trial';
  code_name: string;
  cohort: string;
  protocol: string;
  indication: string;
  adverse_choices: string[];
  subjects: medicalTrialSubject[];
  analysis_ready: BooleanLike;
  resupplies_remaining: number;
  resupply_cost: number;
};

export type medicalCaseReportDetails = {
  kind: 'medical_case_report';
  patient: string;
  condition: string;
  consented: BooleanLike;
};

export type socialStakeholderProposal = {
  account: number;
  name: string;
  department?: string;
  weight: number;
  approved_weight: number;
  status: string;
  contribution: number;
  qualified: BooleanLike;
  online: BooleanLike;
};

export type socialStakeholderRole = {
  id: string;
  title: string;
  description: string;
  departments: string[];
  minimum: number;
  authored_minimum: number;
  maximum: number;
  approved: number;
  qualified: number;
  minimum_contribution: number;
  viewer_eligible: BooleanLike;
  viewer_has_other_role: BooleanLike;
  proposals: socialStakeholderProposal[];
};

export type socialOutcomeDetails = {
  kind: 'social_outcome';
  grade: string;
  projected_grade: string;
  projected_reward: number;
  earned_reward: number;
  score: number;
  outcome_stages: contractOutcomeStage[];
  minimum_percent: number;
  success_percent: number;
  exceptional_percent: number;
  can_finalize: BooleanLike;
  stakeholders_ready: BooleanLike;
  stakeholder_required: number;
  stakeholder_qualified: number;
  stakeholder_summary: string;
  roles: socialStakeholderRole[];
};

export type contractOutcomeStage = {
  label: string;
  target: number;
  reward: number;
  reached: BooleanLike;
  earned: BooleanLike;
};

export type financeTransaction = {
  date: string;
  time: string;
  target: string;
  purpose: string;
  amount: string | number;
  terminal: string;
};

export type financeIncomeSource = {
  source: string;
  amount: number;
};

export type departmentFinance = {
  department: string;
  balance: number;
  savings: number;
  monthly_allocation: number;
  automatic_allocation: number;
  funded_allocation: number;
  allocation_shortfall: number;
  allocation_overridden: BooleanLike;
  allocation_percent: number;
  employee_count: number;
  operating_allocation: number;
  operating_funded: number;
  payroll_funded: number;
  monthly_income: number;
  monthly_expenses: number;
  last_month_income: number;
  last_month_expenses: number;
  projected_payroll: number;
  payroll_resources: number;
  payroll_coverage: number;
  last_payroll_due: number;
  last_payroll_paid: number;
  last_payroll_shortfall: number;
  revenue: number;
  expenses: number;
  wage_multiplier: number;
  service_subsidy: number;
  service_invoices: serviceInvoiceSummary;
  income_sources: financeIncomeSource[];
  transactions: financeTransaction[];
};

export type budgetPlan = {
  projected_payroll: number;
  nt_grant: number;
  available: number;
  operating_pool: number;
  operating_requested: number;
  operating_funded: number;
  payroll_funded: number;
  unallocated_operating: number;
  requested: number;
  funded: number;
  remaining: number;
  shortfall: number;
};

export type serviceInvoiceSummary = {
  invoice_count: number;
  refund_count: number;
  gross_billed: number;
  refunded_total: number;
  net_billed: number;
  account_sales: number;
  cash_sales: number;
  ewallet_sales: number;
  tips: number;
  staff_tips: number;
  service_tips: number;
};

export type record = { ref: string; id: string; name: string; b_dna: string };

export type field = {
  field: string;
  value: string | number;
  edit: string | null;
};
