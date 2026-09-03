import { Fragment, useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Dropdown,
  LabeledList,
  ProgressBar,
  Section,
  Stack,
  Table,
  Tooltip,
} from 'tgui-core/components';

import type { contractClauseOption, Data, managementContract } from './types';

const signed = (value: number, suffix = '') =>
  `${value > 0 ? '+' : ''}${value}${suffix}`;

const reputationChange = (value: number) => {
  const magnitude = Math.abs(value);
  if (!magnitude) {
    return '—';
  }
  const marks = magnitude <= 9 ? 1 : magnitude <= 19 ? 2 : 3;
  return Array(marks)
    .fill(value > 0 ? '+' : '−')
    .join('\u2009');
};

const reputationDescription = (value: number) => {
  const magnitude = Math.abs(value);
  if (!magnitude) {
    return 'no reputation change';
  }
  const degree =
    magnitude <= 9 ? 'small' : magnitude <= 19 ? 'moderate' : 'large';
  return `${degree} reputation ${value < 0 ? 'decrease' : 'increase'}`;
};

const FactionBadge = ({
  acronym,
  color,
}: {
  acronym: string;
  color: string;
}) => (
  <Box inline bold px={0.5} backgroundColor={color} color="white">
    {acronym}
  </Box>
);

const TermTooltip = ({
  option,
  contract,
}: {
  option: contractClauseOption;
  contract: managementContract;
}) => {
  const effects: [string, number, number][] = [
    ['Station', option.station_money, option.station_reputation],
    [
      contract.department || 'Department',
      option.department_money,
      option.department_reputation,
    ],
    ['Staff', option.staff_money, option.staff_reputation],
  ];
  const visibleEffects = effects.filter(
    ([label, money, reputation]) =>
      !!money ||
      !!reputation ||
      (label === 'Station' && !!option.other_reputation.length),
  );

  return (
    <Box width="225px">
      <Box mb={0.75}>{option.description}</Box>
      {!!visibleEffects.length && (
        <Box p={0.5} mb={0.5} backgroundColor="rgba(255, 255, 255, 0.055)">
          <Box bold mb={0.5} color="label">
            Award adjustment
          </Box>
          <Table>
            {visibleEffects.map(([label, money, reputation]) => (
              <Table.Row key={label}>
                <Table.Cell bold width="68px">
                  {label}
                </Table.Cell>
                <Table.Cell textAlign="right" width="55px" pr={0.5} nowrap>
                  <Box
                    inline
                    color={money < 0 ? 'bad' : money > 0 ? 'good' : 'label'}
                  >
                    {money ? signed(money, ' th') : '—'}
                  </Box>
                </Table.Cell>
                <Table.Cell>
                  {!!reputation && (
                    <Box inline mr={0.75} nowrap>
                      <FactionBadge
                        acronym={contract.issuer_acronym}
                        color={contract.issuer_color}
                      />{' '}
                      <Box inline color={reputation < 0 ? 'bad' : 'good'}>
                        {reputationChange(reputation)}
                      </Box>
                    </Box>
                  )}
                  {label === 'Station' &&
                    option.other_reputation.map((change) => (
                      <Box key={change.faction} inline mr={0.75} nowrap>
                        <FactionBadge
                          acronym={change.acronym}
                          color={change.color}
                        />{' '}
                        <Box inline color={change.amount < 0 ? 'bad' : 'good'}>
                          {reputationChange(change.amount)}
                        </Box>
                      </Box>
                    ))}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Box>
      )}
      {!!option.deadline_minutes && (
        <Box color="label" nowrap>
          Deadline adjustment:{' '}
          <Box inline bold color={option.deadline_minutes < 0 ? 'bad' : 'good'}>
            {signed(option.deadline_minutes, ' min')}
          </Box>
        </Box>
      )}
    </Box>
  );
};

const RewardSummary = ({ contract }: { contract: managementContract }) => {
  const recipients = [
    [
      'Station',
      contract.reward_distribution.station,
      contract.reputation_distribution.station,
      true,
    ],
    [
      contract.department || 'Department',
      contract.reward_distribution.department,
      contract.reputation_distribution.department,
      false,
    ],
    [
      'Contributing staff',
      contract.reward_distribution.staff,
      contract.reputation_distribution.staff,
      false,
    ],
  ] as [string, number, number, boolean][];

  return (
    <Stack align="stretch" mt={1}>
      {recipients.map(([label, money, reputation, isStation]) => (
        <Stack.Item key={label} grow>
          <Tooltip
            content={`${label}: ${money.toLocaleString()} Thalers; ${reputationDescription(reputation)} with ${contract.issuer_faction}${isStation && contract.secondary_reputation.length ? `; ${contract.secondary_reputation.map((change) => `${reputationDescription(change.amount)} with ${change.faction}`).join('; ')}` : ''}`}
          >
            <Box
              height="100%"
              p={0.5}
              textAlign="center"
              backgroundColor="rgba(255, 255, 255, 0.055)"
            >
              <Box color="label" mb={0.25}>
                {label}
              </Box>
              <Box inline bold>
                {money.toLocaleString()} th
              </Box>
              {!!reputation && (
                <Box inline ml={0.75}>
                  <FactionBadge
                    acronym={contract.issuer_acronym}
                    color={contract.issuer_color}
                  />{' '}
                  <Box inline color={reputation < 0 ? 'bad' : 'good'}>
                    {reputationChange(reputation)}
                  </Box>
                </Box>
              )}
              {isStation &&
                contract.secondary_reputation.map((change) => (
                  <Box key={change.faction} inline ml={0.75} nowrap>
                    <FactionBadge
                      acronym={change.acronym}
                      color={change.color}
                    />{' '}
                    <Box inline color={change.amount < 0 ? 'bad' : 'good'}>
                      {reputationChange(change.amount)}
                    </Box>
                  </Box>
                ))}
            </Box>
          </Tooltip>
        </Stack.Item>
      ))}
    </Stack>
  );
};

const lifecycleGroups = [
  { id: 'offers', label: 'Offers', states: ['offered'] },
  { id: 'current', label: 'In Progress', states: ['active', 'grace'] },
  {
    id: 'history',
    label: 'History',
    states: ['completed', 'failed', 'cancelled'],
  },
];

export const ManagementContracts = () => {
  const { act, data } = useBackend<Data>();
  const [selectedStatus, setSelectedStatus] = useState('offers');
  const [selectedDepartment, setSelectedDepartment] = useState('All');
  const [selectedType, setSelectedType] = useState('All');
  const [trialAdverse, setTrialAdverse] = useState('none');
  const [expandedContracts, setExpandedContracts] = useState<
    Record<string, boolean>
  >({});
  const [expandedRequirements, setExpandedRequirements] = useState<
    Record<string, boolean>
  >({});
  const [expandedStakeholders, setExpandedStakeholders] = useState<
    Record<string, boolean>
  >({});
  const lifecycle =
    lifecycleGroups.find((group) => group.id === selectedStatus) ??
    lifecycleGroups[0];
  const selectedStatusLabel =
    selectedStatus === 'all' ? 'All' : lifecycle.label;
  const reputationDepartment =
    selectedDepartment === 'All' || selectedDepartment === 'Station-wide'
      ? undefined
      : selectedDepartment;
  const departmentOptions = [
    'All',
    'Station-wide',
    ...(data.contract_departments ?? []),
  ];
  const contracts = (data.contracts ?? []).filter((contract) => {
    if (
      selectedStatus !== 'all' &&
      !lifecycle.states.includes(contract.state)
    ) {
      return false;
    }
    if (
      selectedDepartment !== 'All' &&
      (selectedDepartment === 'Station-wide'
        ? contract.scope !== 'station'
        : contract.department !== selectedDepartment)
    ) {
      return false;
    }
    if (selectedType !== 'All' && contract.term_class !== selectedType) {
      return false;
    }
    return true;
  });

  return (
    <Box>
      <Stack align="center" mb={1} p={0.75} backgroundColor="rgba(0,0,0,0.2)">
        <Stack.Item grow>
          <Stack align="center">
            <Stack.Item color="label">Department</Stack.Item>
            <Stack.Item grow>
              <Dropdown
                fluid
                selected={selectedDepartment}
                options={departmentOptions}
                onSelected={(value) => setSelectedDepartment(String(value))}
              />
            </Stack.Item>
          </Stack>
        </Stack.Item>
        <Stack.Item grow>
          <Stack align="center">
            <Stack.Item color="label">Status</Stack.Item>
            <Stack.Item grow>
              <Dropdown
                fluid
                selected={selectedStatusLabel}
                options={[
                  { displayText: 'All', value: 'all' },
                  ...lifecycleGroups.map((group) => ({
                    displayText: group.label,
                    value: group.id,
                  })),
                ]}
                onSelected={(value) => setSelectedStatus(String(value))}
              />
            </Stack.Item>
          </Stack>
        </Stack.Item>
        <Stack.Item grow>
          <Stack align="center">
            <Stack.Item color="label">Type</Stack.Item>
            <Stack.Item grow>
              <Dropdown
                fluid
                selected={selectedType}
                options={[
                  { displayText: 'All', value: 'All' },
                  { displayText: 'Short-term', value: 'short' },
                  { displayText: 'Long-term', value: 'long' },
                ]}
                onSelected={(value) => setSelectedType(String(value))}
              />
            </Stack.Item>
          </Stack>
        </Stack.Item>
      </Stack>
      <Stack
        align="center"
        mb={1}
        px={0.75}
        py={0.5}
        backgroundColor="rgba(0,0,0,0.2)"
      >
        <Stack.Item color="label" nowrap>
          {reputationDepartment
            ? `${reputationDepartment} reputation`
            : 'Station reputation'}
        </Stack.Item>
        {(data.contract_faction_standings ?? []).map((faction) => (
          <Stack.Item key={faction.acronym} grow textAlign="center" nowrap>
            <Tooltip content={faction.name}>
              <Box inline>
                <Box inline bold color={faction.color} mr={0.5}>
                  {faction.acronym}
                </Box>
                <Box inline color="label">
                  {reputationDepartment
                    ? (faction.department_tiers?.[reputationDepartment] ??
                      faction.tier)
                    : faction.tier}
                </Box>
              </Box>
            </Tooltip>
          </Stack.Item>
        ))}
      </Stack>
      {!contracts.length && (
        <Box p={4} textAlign="center" color="label">
          No contracts match this view.
        </Box>
      )}
      {contracts.map((contract, index) => {
        const expanded = !!expandedContracts[contract.id];
        const requirementsExpanded = !!expandedRequirements[contract.id];
        const stakeholdersExpanded = !!expandedStakeholders[contract.id];
        return (
          <Fragment key={contract.id}>
            <Section
              title={`${contract.id} — ${contract.title}`}
              buttons={
                <Stack>
                  {contract.state === 'offered' && (
                    <Stack.Item>
                      <Button
                        icon="file-signature"
                        disabled={!contract.can_accept}
                        onClick={() =>
                          act('contract_accept', { id: contract.id })
                        }
                      >
                        Accept Selected Terms
                      </Button>
                    </Stack.Item>
                  )}
                  <Stack.Item>
                    <Button
                      icon={expanded ? 'chevron-up' : 'chevron-down'}
                      onClick={() =>
                        setExpandedContracts((current) => ({
                          ...current,
                          [contract.id]: !expanded,
                        }))
                      }
                    >
                      {expanded ? 'Collapse' : 'Details'}
                    </Button>
                  </Stack.Item>
                </Stack>
              }
              style={{
                border: '1px solid rgba(255, 255, 255, 0.08)',
                borderLeft: `4px solid ${contract.issuer_color}`,
                backgroundColor: 'rgba(8, 10, 12, 0.72)',
                marginBottom: index < contracts.length - 1 ? '6px' : undefined,
              }}
            >
              {!expanded && (
                <Stack align="center">
                  <Stack.Item grow color="label">
                    {contract.issuer_acronym} ·{' '}
                    {contract.department || 'Station-wide'} ·{' '}
                    {contract.term_class === 'short'
                      ? 'Short-term'
                      : 'Long-term'}
                  </Stack.Item>
                  <Stack.Item bold>
                    {contract.reward.toLocaleString()} th
                  </Stack.Item>
                </Stack>
              )}
              {expanded && (
                <Box>
                  <LabeledList>
                    <LabeledList.Item label="Issuer">
                      <Box
                        inline
                        bold
                        mr={0.5}
                        px={0.5}
                        backgroundColor={contract.issuer_color}
                        color="white"
                      >
                        {contract.issuer_acronym}
                      </Box>
                      {contract.issuer}
                    </LabeledList.Item>
                    <LabeledList.Item label="Scope">
                      {contract.offer_kind === 'standing'
                        ? 'Rotating offer'
                        : 'Limited opportunity'}{' '}
                      ·{' '}
                      {contract.term_class === 'short'
                        ? 'Short-term'
                        : 'Long-term'}
                      {contract.scope === 'station' ? ' · Station-wide' : ''}
                      {contract.department ? ` · ${contract.department}` : ''}
                    </LabeledList.Item>
                    <LabeledList.Item label="Sponsor standing">
                      {contract.standing_tier}
                      {!!contract.standing_reward_modifier && (
                        <Box
                          inline
                          ml={0.75}
                          color={
                            contract.standing_reward_modifier > 0
                              ? 'good'
                              : 'bad'
                          }
                        >
                          {signed(contract.standing_reward_modifier, '%')}
                        </Box>
                      )}
                    </LabeledList.Item>
                    {contract.offer_time_remaining && (
                      <LabeledList.Item label="Offer expires">
                        {contract.offer_time_remaining}
                      </LabeledList.Item>
                    )}
                    {contract.deadline_remaining && (
                      <LabeledList.Item label="Time remaining">
                        {contract.deadline_remaining}
                      </LabeledList.Item>
                    )}
                    {contract.grace_time_remaining && (
                      <LabeledList.Item label="Evidence grace">
                        {contract.grace_time_remaining}
                      </LabeledList.Item>
                    )}
                  </LabeledList>
                  <Box my={1}>{contract.description}</Box>
                  <RewardSummary contract={contract} />
                  {!!contract.negotiation_clauses.length && (
                    <Section
                      mt={1}
                      title="Terms"
                      buttons={
                        contract.negotiation_locked && (
                          <Tooltip content="Terms were locked when this contract was accepted.">
                            <Box color="label">Locked</Box>
                          </Tooltip>
                        )
                      }
                    >
                      {contract.negotiation_clauses.map((clause) => (
                        <Stack
                          key={`${contract.id}-${clause.id}`}
                          align="center"
                          minHeight="28px"
                          py={0.25}
                        >
                          <Stack.Item basis="22%">
                            <Tooltip content={clause.description}>
                              <Box bold>{clause.title}</Box>
                            </Tooltip>
                          </Stack.Item>
                          <Stack.Item grow>
                            <Stack>
                              {clause.options.map((option) => {
                                const selected = clause.selected === option.id;
                                return (
                                  <Stack.Item key={option.id} grow>
                                    <Tooltip
                                      content={
                                        <TermTooltip
                                          option={option}
                                          contract={contract}
                                        />
                                      }
                                    >
                                      <Button
                                        fluid
                                        compact
                                        textAlign="center"
                                        selected={selected}
                                        color={selected ? 'good' : undefined}
                                        disabled={
                                          !!contract.negotiation_locked ||
                                          !contract.can_accept
                                        }
                                        onClick={() =>
                                          act('contract_negotiate', {
                                            id: contract.id,
                                            clause: clause.id,
                                            option: option.id,
                                          })
                                        }
                                      >
                                        {option.title}
                                      </Button>
                                    </Tooltip>
                                  </Stack.Item>
                                );
                              })}
                            </Stack>
                          </Stack.Item>
                        </Stack>
                      ))}
                    </Section>
                  )}
                  {!!contract.requirements.length && (
                    <Section
                      mt={1}
                      title={`Requirements (${contract.requirements.length})`}
                      buttons={
                        <Button
                          compact
                          icon={
                            requirementsExpanded ? 'chevron-up' : 'chevron-down'
                          }
                          onClick={() =>
                            setExpandedRequirements((current) => ({
                              ...current,
                              [contract.id]: !requirementsExpanded,
                            }))
                          }
                        >
                          {requirementsExpanded ? 'Hide' : 'Show'}
                        </Button>
                      }
                    >
                      {requirementsExpanded &&
                        contract.requirements.map((requirement) => (
                          <Box
                            key={`${contract.id}-${requirement.name}`}
                            mb={1}
                          >
                            <Box bold>
                              {requirement.name} — {requirement.progress_text}
                            </Box>
                            <Box color="label">{requirement.description}</Box>
                            <ProgressBar
                              value={requirement.progress}
                              minValue={0}
                              maxValue={requirement.target}
                            />
                          </Box>
                        ))}
                    </Section>
                  )}
                  {contract.details?.kind === 'social_outcome' && (
                    <Section
                      mt={1}
                      title={`Stakeholders and settlement — ${contract.details.stakeholder_summary}`}
                      buttons={
                        <Stack>
                          {stakeholdersExpanded &&
                            ['active', 'grace'].includes(contract.state) && (
                              <Stack.Item>
                                <Button
                                  icon="flag-checkered"
                                  color="good"
                                  disabled={!contract.details.can_finalize}
                                  tooltip="Settle at the currently projected grade. This cannot be undone."
                                  onClick={() =>
                                    act('contract_finalize_outcome', {
                                      id: contract.id,
                                    })
                                  }
                                >
                                  Finalize {contract.details.projected_grade}{' '}
                                  outcome
                                </Button>
                              </Stack.Item>
                            )}
                          <Stack.Item>
                            <Button
                              compact
                              icon={
                                stakeholdersExpanded
                                  ? 'chevron-up'
                                  : 'chevron-down'
                              }
                              onClick={() =>
                                setExpandedStakeholders((current) => ({
                                  ...current,
                                  [contract.id]: !stakeholdersExpanded,
                                }))
                              }
                            >
                              {stakeholdersExpanded ? 'Hide' : 'Show'}
                            </Button>
                          </Stack.Item>
                        </Stack>
                      }
                    >
                      {stakeholdersExpanded && (
                        <Box>
                          <Box bold>
                            Current specification: {contract.details.score}% ·
                            projected {contract.details.projected_grade} ·{' '}
                            {contract.details.projected_reward} Thalers
                          </Box>
                          <ProgressBar
                            value={contract.details.score}
                            minValue={0}
                            maxValue={100}
                            ranges={{
                              bad: [0, contract.details.minimum_percent],
                              average: [
                                contract.details.minimum_percent,
                                contract.details.success_percent,
                              ],
                              good: [contract.details.success_percent, 100],
                            }}
                          />
                          <Box mt={0.5} color="label">
                            Minimum settlement begins at{' '}
                            {contract.details.minimum_percent}
                            %; certified at {contract.details.success_percent}
                            %; exceptional at{' '}
                            {contract.details.exceptional_percent}%. Every
                            required dimension and stakeholder role must meet
                            its negotiated minimum.
                          </Box>
                          <Box mt={0.5} color="label">
                            Share weights divide the fixed staff award; they do
                            not increase it. Approval reserves a role, while
                            attributable contract work qualifies it for
                            settlement.
                          </Box>
                          {contract.details.roles.map((role) => (
                            <Section
                              key={`${contract.id}-${role.id}`}
                              mt={1}
                              title={`${role.title} — ${role.qualified}/${role.minimum} qualified · ${role.approved} approved`}
                            >
                              <Box mb={0.5} color="label">
                                {role.description}
                                {role.authored_minimum > role.minimum && (
                                  <>
                                    {' '}
                                    Staffing reduced the required slate from{' '}
                                    {role.authored_minimum} to {role.minimum}.
                                    Remaining appointments are optional.
                                  </>
                                )}
                              </Box>
                              {!role.proposals.length && (
                                <Box color="label">
                                  No participation proposals filed.
                                </Box>
                              )}
                              {role.proposals.map((proposal) => (
                                <Stack
                                  key={`${role.id}-${proposal.account}`}
                                  align="center"
                                  mb={0.5}
                                >
                                  <Stack.Item grow>
                                    <Box bold>{proposal.name}</Box>
                                    <Box color="label">
                                      {proposal.department || 'Independent'} ·
                                      {proposal.online ? 'online' : 'offline'} ·
                                      requested {proposal.weight}× share
                                      {!!proposal.approved_weight &&
                                        ` · offered ${proposal.approved_weight}×`}
                                      {' · '}contribution{' '}
                                      {proposal.contribution}/
                                      {role.minimum_contribution} ·{' '}
                                      {proposal.qualified
                                        ? 'qualified'
                                        : proposal.status}
                                    </Box>
                                  </Stack.Item>
                                  {[
                                    'pending',
                                    'countered',
                                    'approved',
                                  ].includes(proposal.status) && (
                                    <Stack.Item>
                                      <Stack align="center">
                                        <Stack.Item color="label">
                                          {proposal.status === 'approved'
                                            ? 'Share'
                                            : 'Offer'}
                                        </Stack.Item>
                                        {[1, 2, 3].map((weight) => (
                                          <Stack.Item key={weight}>
                                            <Button
                                              compact
                                              selected={
                                                proposal.status ===
                                                  'approved' &&
                                                proposal.approved_weight ===
                                                  weight
                                              }
                                              tooltip={
                                                weight === proposal.weight
                                                  ? 'Approve the requested share'
                                                  : 'Send this counteroffer'
                                              }
                                              onClick={() =>
                                                act(
                                                  'contract_stakeholder_decide',
                                                  {
                                                    id: contract.id,
                                                    account: proposal.account,
                                                    role: role.id,
                                                    approved: 1,
                                                    weight,
                                                  },
                                                )
                                              }
                                            >
                                              {weight}×
                                            </Button>
                                          </Stack.Item>
                                        ))}
                                        {proposal.status === 'pending' && (
                                          <Stack.Item>
                                            <Button
                                              compact
                                              icon="times"
                                              color="bad"
                                              tooltip="Reject this application"
                                              onClick={() =>
                                                act(
                                                  'contract_stakeholder_decide',
                                                  {
                                                    id: contract.id,
                                                    account: proposal.account,
                                                    role: role.id,
                                                    approved: 0,
                                                  },
                                                )
                                              }
                                            />
                                          </Stack.Item>
                                        )}
                                      </Stack>
                                    </Stack.Item>
                                  )}
                                  {['approved', 'countered'].includes(
                                    proposal.status,
                                  ) && (
                                    <Stack.Item>
                                      <Button
                                        compact
                                        icon="user-minus"
                                        color="bad"
                                        tooltip="Revoke this appointment so the role can be filled again"
                                        onClick={() =>
                                          act('contract_stakeholder_revoke', {
                                            id: contract.id,
                                            account: proposal.account,
                                            role: role.id,
                                          })
                                        }
                                      />
                                    </Stack.Item>
                                  )}
                                </Stack>
                              ))}
                            </Section>
                          ))}
                        </Box>
                      )}
                    </Section>
                  )}
                  {contract.details?.kind === 'medical_trial' && (
                    <Section
                      mt={1}
                      title={`${contract.details.code_name} Clinical Dashboard`}
                      buttons={
                        contract.state === 'active' && (
                          <Stack>
                            <Stack.Item>
                              <Button
                                icon="prescription-bottle-medical"
                                disabled={
                                  !contract.details.resupplies_remaining
                                }
                                tooltip={`${contract.details.resupply_cost} Thalers from Medical's budget; ${contract.details.resupplies_remaining} remaining`}
                                onClick={() =>
                                  act('contract_resupply_trial', {
                                    id: contract.id,
                                  })
                                }
                              >
                                Replacement Dose
                              </Button>
                            </Stack.Item>
                            <Stack.Item>
                              <Button
                                icon="print"
                                onClick={() =>
                                  act('contract_print_trial_packet', {
                                    id: contract.id,
                                  })
                                }
                              >
                                Print Consent Record
                              </Button>
                            </Stack.Item>
                          </Stack>
                        )
                      }
                    >
                      <LabeledList>
                        <LabeledList.Item label="Cohort">
                          {contract.details.cohort}
                        </LabeledList.Item>
                        <LabeledList.Item label="Declared indication">
                          {contract.details.indication}
                        </LabeledList.Item>
                        <LabeledList.Item label="Protocol">
                          {contract.details.protocol}
                        </LabeledList.Item>
                        <LabeledList.Item label="Submission">
                          For each subject, bundle the signed consent with a
                          body scan printed before exposure and another printed
                          at least one minute afterward. Fax that bundle to
                          VeyMed Clinical Development. File the final
                          interpretation there after all three evidence packets
                          are accepted.
                        </LabeledList.Item>
                      </LabeledList>
                      {!contract.details.subjects.length && (
                        <Box mt={1} color="label">
                          No signed consent records have been registered.
                        </Box>
                      )}
                      {contract.details.subjects.map((subject) => (
                        <Section
                          key={subject.subject_ref}
                          mt={1}
                          title={`${subject.name} — ${subject.cohort_class}`}
                          buttons={
                            <Stack align="center">
                              <Stack.Item>
                                <Box color="label">{subject.status}</Box>
                              </Stack.Item>
                              {!!subject.can_reissue && (
                                <Stack.Item>
                                  <Button
                                    icon="print"
                                    tooltip="Print a certified replacement for a lost or destroyed consent record."
                                    onClick={() =>
                                      act('contract_reissue_trial_packet', {
                                        id: contract.id,
                                        subject_id: subject.subject_ref,
                                      })
                                    }
                                  >
                                    Replacement Record
                                  </Button>
                                </Stack.Item>
                              )}
                              {!!subject.can_revoke && (
                                <Stack.Item>
                                  <Button
                                    icon="user-slash"
                                    color="warning"
                                    tooltip="Print an ordinary withdrawal form for the patient to sign and fax."
                                    onClick={() =>
                                      act('contract_print_trial_revocation', {
                                        id: contract.id,
                                        subject_id: subject.subject_ref,
                                      })
                                    }
                                  >
                                    Withdrawal Form
                                  </Button>
                                </Stack.Item>
                              )}
                            </Stack>
                          }
                        >
                          <LabeledList>
                            <LabeledList.Item label="Tracer">
                              {subject.marker_detected
                                ? 'Detected in current body'
                                : 'Not presently detected'}
                            </LabeledList.Item>
                            <LabeledList.Item label="Next step">
                              {subject.next_step}
                            </LabeledList.Item>
                          </LabeledList>
                          Clinical findings remain on the physical scanner
                          printouts.
                        </Section>
                      ))}
                      {contract.state === 'active' && (
                        <Stack mt={1} align="center">
                          <Stack.Item grow>
                            <Dropdown
                              selected={trialAdverse}
                              options={contract.details.adverse_choices}
                              onSelected={(value) =>
                                setTrialAdverse(String(value))
                              }
                            />
                          </Stack.Item>
                          <Stack.Item>
                            <Button
                              icon="file-export"
                              disabled={!contract.details.analysis_ready}
                              onClick={() =>
                                act('contract_print_trial_report', {
                                  id: contract.id,
                                  adverse: trialAdverse,
                                })
                              }
                            >
                              Print Final Report
                            </Button>
                          </Stack.Item>
                        </Stack>
                      )}
                    </Section>
                  )}
                  {contract.details?.kind === 'medical_case_report' && (
                    <Section
                      mt={1}
                      title="Clinical Case Registry"
                      buttons={
                        contract.state === 'active' && (
                          <Stack>
                            <Stack.Item>
                              <Button
                                icon="print"
                                onClick={() =>
                                  act('contract_print_case_forms', {
                                    id: contract.id,
                                  })
                                }
                              >
                                {contract.details.consented
                                  ? 'Replacement Case Forms'
                                  : 'Print Case Forms'}
                              </Button>
                            </Stack.Item>
                            {!!contract.details.consented && (
                              <Stack.Item>
                                <Button
                                  icon="user-slash"
                                  color="warning"
                                  onClick={() =>
                                    act('contract_print_case_revocation', {
                                      id: contract.id,
                                    })
                                  }
                                >
                                  Withdrawal Form
                                </Button>
                              </Stack.Item>
                            )}
                          </Stack>
                        )
                      }
                    >
                      <LabeledList>
                        <LabeledList.Item label="Patient">
                          {contract.details.patient}
                        </LabeledList.Item>
                        <LabeledList.Item label="Presentation">
                          {contract.details.condition}
                        </LabeledList.Item>
                        <LabeledList.Item label="Consent">
                          {contract.details.consented
                            ? 'Registered'
                            : 'Awaiting patient signature'}
                        </LabeledList.Item>
                        <LabeledList.Item label="Submission">
                          Fax the signed consent, completed treatment/outcome
                          narrative, qualifying baseline scan, and one-minute
                          follow-up scan to the VeyMed Clinical Case Registry.
                        </LabeledList.Item>
                      </LabeledList>
                    </Section>
                  )}
                </Box>
              )}
            </Section>
          </Fragment>
        );
      })}
    </Box>
  );
};
