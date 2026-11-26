import type { BooleanLike } from 'tgui-core/react';

import type { GeneralRecordsData } from '../generated/GeneralRecords';

type RawContract = GeneralRecordsData['contracts'][number];

// ui_details() of a contract is a different shape per contract kind, so the generated type leaves it an open row: the kinds the window renders are typed here.
export type managementContract = Omit<RawContract, 'details'> & {
  details: contractDetails | null;
};

export type Data = Omit<GeneralRecordsData, 'contracts'> & {
  contracts: managementContract[];
};

export type factionStanding = Data['contract_faction_standings'][number];

export type contractRequirement = managementContract['requirements'][number];

export type contractRequirementStage = contractRequirement['stages'][number];

export type contractDistribution = managementContract['reward_distribution'];

export type contractNegotiationClause =
  managementContract['negotiation_clauses'][number];

export type contractClauseOption = contractNegotiationClause['options'][number];

export type factionReputationChange =
  managementContract['secondary_reputation'][number];

export type contractDetails =
  | medicalTrialDetails
  | medicalCaseReportDetails
  | socialOutcomeDetails;

export type medicalTrialSubject = {
  name: string;
  subject_ref: number;
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

export type financeTransaction = Data['station_transactions'][number];

export type financeIncomeSource = Data['station_income_sources'][number];

export type departmentFinance = Data['department_finances'][number];

export type budgetPlan = NonNullable<Data['budget_plan']>;

export type serviceInvoiceSummary = departmentFinance['service_invoices'];

export type record = NonNullable<Data['records']>[number];

export type field = NonNullable<NonNullable<Data['general']>['fields']>[number];
