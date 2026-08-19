import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Dropdown,
  LabeledList,
  ProgressBar,
  Section,
  Stack,
  Tabs,
} from 'tgui-core/components';

import type { contractClauseOption, Data } from './types';

const signed = (value: number, suffix = '') =>
  `${value > 0 ? '+' : ''}${value}${suffix}`;

const TermEffects = ({ option }: { option: contractClauseOption }) => {
  const effects: [string, number, number][] = [
    ['Station', option.station_money, option.station_reputation],
    ['Department', option.department_money, option.department_reputation],
    ['Staff', option.staff_money, option.staff_reputation],
  ];

  return (
    <Stack mt={0.5} wrap>
      {effects.map(([label, money, reputation]) => (
        <Stack.Item key={String(label)}>
          <Box color="label" inline>
            {label}:{' '}
          </Box>
          <Box inline color={Number(money) < 0 ? 'bad' : undefined}>
            {signed(Number(money), ' th')}
          </Box>
          {' / '}
          <Box inline color={Number(reputation) < 0 ? 'bad' : undefined}>
            {signed(Number(reputation), ' rep')}
          </Box>
        </Stack.Item>
      ))}
      {!!option.deadline_minutes && (
        <Stack.Item>
          <Box color="label" inline>
            Deadline:{' '}
          </Box>
          <Box inline color={option.deadline_minutes < 0 ? 'bad' : 'good'}>
            {signed(option.deadline_minutes, ' min')}
          </Box>
        </Stack.Item>
      )}
    </Stack>
  );
};

const states = [
  'offered',
  'active',
  'grace',
  'completed',
  'failed',
  'cancelled',
];

export const ManagementContracts = () => {
  const { act, data } = useBackend<Data>();
  const [selectedState, setSelectedState] = useState('offered');
  const [trialAdverse, setTrialAdverse] = useState('none');
  const contracts = (data.contracts ?? []).filter(
    (contract) => contract.state === selectedState,
  );

  return (
    <Box>
      <Tabs fluid>
        {states.map((state) => (
          <Tabs.Tab
            key={state}
            selected={selectedState === state}
            onClick={() => setSelectedState(state)}
          >
            {state.charAt(0).toUpperCase() + state.slice(1)}
          </Tabs.Tab>
        ))}
      </Tabs>
      {!contracts.length && (
        <Box p={4} textAlign="center" color="label">
          No {selectedState} station or department contracts are available to
          this console.
        </Box>
      )}
      {contracts.map((contract) => (
        <Section
          key={contract.id}
          title={`${contract.id} — ${contract.title}`}
          buttons={
            contract.state === 'offered' && (
              <Stack>
                <Stack.Item>
                  <Button
                    icon="file-signature"
                    disabled={!contract.can_accept}
                    onClick={() => act('contract_accept', { id: contract.id })}
                  >
                    Accept Selected Terms
                  </Button>
                </Stack.Item>
                <Stack.Item>
                  <Button
                    icon="ban"
                    color="bad"
                    disabled={!contract.can_decline}
                    onClick={() => act('contract_decline', { id: contract.id })}
                  >
                    Decline
                  </Button>
                </Stack.Item>
              </Stack>
            )
          }
          style={{ borderLeft: `4px solid ${contract.issuer_color}` }}
        >
          <LabeledList>
            <LabeledList.Item label="Issuer">
              {contract.issuer}
            </LabeledList.Item>
            <LabeledList.Item label="Scope">
              {contract.offer_kind === 'standing'
                ? 'Standing offer'
                : 'Limited opportunity'}{' '}
              · {contract.scope}
              {contract.department ? ` · ${contract.department}` : ''}
            </LabeledList.Item>
            <LabeledList.Item label="Reward">
              {contract.reward} Thalers
            </LabeledList.Item>
            <LabeledList.Item label="Sponsor standing">
              {contract.standing_tier} ({contract.standing_score})
            </LabeledList.Item>
            <LabeledList.Item label="Market demand">
              Commission #{contract.repeat_index}
              {contract.round_demand_remaining >= 0
                ? ` · ${contract.round_demand_remaining} award${contract.round_demand_remaining === 1 ? '' : 's'} remaining this shift`
                : ' · continuing program'}
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
          {!!contract.negotiation_clauses.length && (
            <Section
              mt={1}
              title="Negotiated Terms"
              buttons={
                <Box color={contract.negotiation_locked ? 'label' : 'good'}>
                  {contract.negotiation_locked
                    ? 'Terms locked'
                    : 'Selections lock immediately when this offer is accepted'}
                </Box>
              }
            >
              <Stack mb={1} justify="space-around">
                <Stack.Item>
                  <Box bold>Station</Box>
                  {contract.reward_distribution.station} th /{' '}
                  {signed(contract.reputation_distribution.station, ' rep')}
                </Stack.Item>
                <Stack.Item>
                  <Box bold>{contract.department || 'Department'}</Box>
                  {contract.reward_distribution.department} th /{' '}
                  {signed(contract.reputation_distribution.department, ' rep')}
                </Stack.Item>
                <Stack.Item>
                  <Box bold>Contributing staff</Box>
                  {contract.reward_distribution.staff} th /{' '}
                  {signed(contract.reputation_distribution.staff, ' rep')}
                </Stack.Item>
              </Stack>
              {contract.negotiation_clauses.map((clause) => (
                <Section
                  key={`${contract.id}-${clause.id}`}
                  title={clause.title}
                  fitted
                  mb={1}
                >
                  <Box mb={1} color="label">
                    {clause.description}
                  </Box>
                  <Stack vertical>
                    {clause.options.map((option) => {
                      const selected = clause.selected === option.id;
                      return (
                        <Stack.Item key={option.id}>
                          <Button
                            fluid
                            selected={selected}
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
                            <Box bold>{option.title}</Box>
                            <Box color="label">{option.description}</Box>
                            <TermEffects option={option} />
                          </Button>
                        </Stack.Item>
                      );
                    })}
                  </Stack>
                </Section>
              ))}
            </Section>
          )}
          {contract.requirements.map((requirement) => (
            <Box key={`${contract.id}-${requirement.name}`} mb={1}>
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
          {contract.details?.kind === 'social_outcome' && (
            <Section
              mt={1}
              title="Stakeholders and graded settlement"
              buttons={
                contract.state === 'active' && (
                  <Button
                    icon="flag-checkered"
                    color="good"
                    disabled={!contract.details.can_finalize}
                    tooltip="Settle at the currently projected grade. This cannot be undone."
                    onClick={() =>
                      act('contract_finalize_outcome', { id: contract.id })
                    }
                  >
                    Finalize {contract.details.projected_grade} outcome
                  </Button>
                )
              }
            >
              <Box bold>
                Current specification: {contract.details.score}% · projected{' '}
                {contract.details.projected_grade} ·{' '}
                {contract.details.projected_reward} Thalers
              </Box>
              <ProgressBar
                value={contract.details.score}
                minValue={0}
                maxValue={100}
                ranges={{
                  bad: [0, 50],
                  average: [50, 75],
                  good: [75, 100],
                }}
              />
              <Box mt={0.5} color="label">
                Minimum settlement begins at 50%; successful at 75%; exceptional
                at 100%. Every required dimension and stakeholder role must meet
                its minimum.
              </Box>
              {contract.details.roles.map((role) => (
                <Section
                  key={`${contract.id}-${role.id}`}
                  mt={1}
                  title={`${role.title} — ${role.approved}/${role.minimum} approved`}
                >
                  <Box mb={0.5} color="label">
                    {role.description}
                  </Box>
                  {!role.proposals.length && (
                    <Box color="label">No participation proposals filed.</Box>
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
                          {proposal.department || 'Independent'} · requested share
                          weight {proposal.weight} · verified contribution{' '}
                          {proposal.contribution} · {proposal.status}
                        </Box>
                      </Stack.Item>
                      {proposal.status === 'pending' && (
                        <Stack.Item>
                          <Button
                            icon="check"
                            color="good"
                            onClick={() =>
                              act('contract_stakeholder_decide', {
                                id: contract.id,
                                account: proposal.account,
                                role: role.id,
                                approved: 1,
                              })
                            }
                          >
                            Approve
                          </Button>
                          <Button
                            icon="times"
                            color="bad"
                            onClick={() =>
                              act('contract_stakeholder_decide', {
                                id: contract.id,
                                account: proposal.account,
                                role: role.id,
                                approved: 0,
                              })
                            }
                          >
                            Reject
                          </Button>
                        </Stack.Item>
                      )}
                    </Stack>
                  ))}
                </Section>
              ))}
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
                        disabled={!contract.details.resupplies_remaining}
                        tooltip={`${contract.details.resupply_cost} Thalers from Medical's budget; ${contract.details.resupplies_remaining} remaining`}
                        onClick={() =>
                          act('contract_resupply_trial', { id: contract.id })
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
                  For each subject, bundle the signed consent with a body scan
                  printed before exposure and another printed at least one
                  minute afterward. Fax that bundle to VeyMed Clinical
                  Development. File the final interpretation there after all
                  three evidence packets are accepted.
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
                  Clinical findings remain on the physical scanner printouts.
                </Section>
              ))}
              {contract.state === 'active' && (
                <Stack mt={1} align="center">
                  <Stack.Item grow>
                    <Dropdown
                      selected={trialAdverse}
                      options={contract.details.adverse_choices}
                      onSelected={(value) => setTrialAdverse(String(value))}
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
                          act('contract_print_case_forms', { id: contract.id })
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
                  Fax the signed consent, completed treatment/outcome narrative,
                  qualifying baseline scan, and one-minute follow-up scan to the
                  VeyMed Clinical Case Registry.
                </LabeledList.Item>
              </LabeledList>
            </Section>
          )}
        </Section>
      ))}
    </Box>
  );
};
