import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  ProgressBar,
  Section,
  Stack,
  Tabs,
} from 'tgui-core/components';

type Contract = {
  id: string;
  title: string;
  description: string;
  state: string;
  issuer: string;
  issuer_color: string;
  reward: number;
  standing_score: number;
  standing_tier: string;
  can_accept: boolean;
  can_decline: boolean;
  offer_kind: string;
  offer_time_remaining?: string;
  deadline_remaining?: string;
  grace_time_remaining?: string;
  requirements: {
    name: string;
    description: string;
    progress: number;
    target: number;
    progress_text: string;
  }[];
  scope: string;
  details?: {
    kind: string;
    grade?: string;
    projected_grade?: string;
    projected_reward?: number;
    score?: number;
    red_contract?: boolean;
    notice?: string;
    tier?: string;
    requires_contact?: boolean;
    contact?: string;
    contact_mode?: string;
    contact_share?: number;
    contact_cooperated?: boolean;
    required_endorsements?: number;
    operation_kind?: string;
    approach?: string;
    approach_name?: string;
    stakeholder_departments?: string[];
    outcome_grade?: string;
    outcome_score?: number;
    discovery_stage?: number;
    discovery_name?: string;
    roles?: {
      id: string;
      title: string;
      description: string;
      viewer_eligible: boolean;
      minimum: number;
      authored_minimum: number;
      approved: number;
      qualified: number;
      minimum_contribution: number;
      viewer_has_other_role: boolean;
      proposals: {
        account: number;
        name: string;
        weight: number;
        approved_weight: number;
        status: string;
        contribution: number;
        qualified: boolean;
        online: boolean;
      }[];
    }[];
    stakeholder_summary?: string;
  };
};

type Data = {
  contracts: Contract[];
  contract_account?: number;
  agents: AgentFaction[];
};

type AgentFaction = {
  id: string;
  name: string;
  short_name: string;
  description: string;
  color: string;
  standing: number;
  standing_tier: string;
  earned: number;
  required_standing: number;
  required_earned: number;
  eligible: boolean;
  active: boolean;
  locked: boolean;
  contracts_completed: number;
  contracts_failed: number;
  tier: number;
  tier_name: string;
  exposure: number;
};

const states = [
  'offered',
  'active',
  'grace',
  'completed',
  'failed',
  'cancelled',
];

export const pda_contracts = () => {
  const { act, data } = useBackend<Data>();
  const [selectedState, setSelectedState] = useState('offered');
  const contracts = (data.contracts ?? []).filter(
    (contract) => contract.state === selectedState,
  );

  if (!data.contract_account) {
    return (
      <Box p={3} textAlign="center" color="bad">
        Insert an ID linked to a personal account to access personal contracts.
      </Box>
    );
  }

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
        <Tabs.Tab
          icon="user-secret"
          selected={selectedState === 'agency'}
          onClick={() => setSelectedState('agency')}
        >
          Agency
        </Tabs.Tab>
      </Tabs>
      {selectedState === 'agency' && (
        <Box>
          <Section title="Faction agency">
            <Box mb={1} color="label">
              Agency is exclusive for the round. Eligibility opens a vetting
              relationship; an authenticated trade grants accreditation, and
              successful commissions can earn trusted status. Agency grants no
              legal immunity or special access.
            </Box>
            <Box
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
                gap: '0.5rem',
              }}
            >
              {(data.agents ?? []).map((faction) => (
                <Section
                  key={faction.id}
                  title={faction.short_name}
                  style={{ borderTop: `3px solid ${faction.color}` }}
                  buttons={
                    faction.active ? (
                      <Button color="good" icon="id-badge" disabled>
                        {faction.tier_name}
                      </Button>
                    ) : (
                      <Button
                        icon="file-signature"
                        disabled={!faction.eligible || faction.locked}
                        onClick={() =>
                          act('contract_agent_apply', { faction: faction.id })
                        }
                      >
                        {faction.locked ? 'Exclusive' : 'Begin vetting'}
                      </Button>
                    )
                  }
                >
                  <Box mb={1} color="label">
                    {faction.description}
                  </Box>
                  <Box bold>
                    Standing: {faction.standing_tier} ({faction.standing})
                  </Box>
                  <ProgressBar
                    value={faction.standing}
                    minValue={-1000}
                    maxValue={faction.required_standing}
                  />
                  <Box mt={0.5} bold>
                    Earned this shift: {faction.earned} /{' '}
                    {faction.required_earned}
                  </Box>
                  <ProgressBar
                    value={faction.earned}
                    minValue={0}
                    maxValue={faction.required_earned}
                  />
                  {!!faction.active && (
                    <Box mt={0.5}>
                      <Box color="average">
                        Commissions: {faction.contracts_completed} completed ·{' '}
                        {faction.contracts_failed} failed
                      </Box>
                      <Box mt={0.5} bold>
                        Operational exposure: {faction.exposure}/100
                      </Box>
                      <ProgressBar
                        value={faction.exposure}
                        minValue={0}
                        maxValue={100}
                        color={faction.exposure >= 40 ? 'bad' : 'average'}
                      />
                      <Box mt={0.5} color="label">
                        Contacts are negotiated per commission using the
                        physical freight agreement issued on acceptance.
                      </Box>
                    </Box>
                  )}
                </Section>
              ))}
            </Box>
          </Section>
        </Box>
      )}
      {selectedState !== 'agency' && (
        <Box>
          {!contracts.length && (
            <Box p={3} textAlign="center" color="label">
              No {selectedState} personal contracts or stakeholder
              opportunities.
            </Box>
          )}
          {contracts.map((contract) => (
            <Section
              key={contract.id}
              title={contract.title}
              buttons={
                contract.state === 'offered' && (
                  <Stack>
                    <Stack.Item>
                      <Button
                        icon="file-signature"
                        disabled={!contract.can_accept}
                        onClick={() =>
                          act('contract_accept', { id: contract.id })
                        }
                      >
                        Accept
                      </Button>
                    </Stack.Item>
                    <Stack.Item>
                      <Button
                        icon="ban"
                        color="bad"
                        disabled={!contract.can_decline}
                        onClick={() =>
                          act('contract_decline', { id: contract.id })
                        }
                      >
                        Decline
                      </Button>
                    </Stack.Item>
                  </Stack>
                )
              }
              style={{ borderLeft: `4px solid ${contract.issuer_color}` }}
            >
              <Box color="label">
                {contract.issuer} · {contract.reward} Thalers ·{' '}
                {contract.offer_kind === 'standing'
                  ? 'standing offer'
                  : 'limited opportunity'}
              </Box>
              <Box color="label">
                Sponsor standing: {contract.standing_tier} (
                {contract.standing_score})
              </Box>
              {contract.offer_time_remaining && (
                <Box color="average">
                  Offer expires in {contract.offer_time_remaining}
                </Box>
              )}
              {contract.deadline_remaining && (
                <Box color="average">
                  Deadline in {contract.deadline_remaining}
                </Box>
              )}
              {contract.grace_time_remaining && (
                <Box color="warning">
                  Evidence grace: {contract.grace_time_remaining}
                </Box>
              )}
              <Box my={1}>{contract.description}</Box>
              {contract.details?.kind === 'faction_agent' && (
                <Section mb={1} title="Field brief">
                  <Box
                    color={contract.details.red_contract ? 'bad' : 'average'}
                  >
                    {contract.details.notice}
                  </Box>
                  {!!contract.details.requires_contact && (
                    <Box mt={0.5} color="label">
                      Recruit an eligible stakeholder face-to-face. The agent
                      must sign the physical operating charter and the contact
                      must choose a compensation and liability line. For freight
                      work, place the signed contact agreement inside the
                      outbound crate.
                    </Box>
                  )}
                  <Box mt={0.5}>
                    Operation: {contract.details.operation_kind ?? 'pending'} ·{' '}
                    approach: {contract.details.approach_name} · outcome:{' '}
                    {contract.details.outcome_score ?? 0}% · discovery:{' '}
                    {contract.details.discovery_name}
                  </Box>
                  {!!contract.details.stakeholder_departments?.length && (
                    <Box mt={0.5} color="label">
                      Stakeholder departments:{' '}
                      {contract.details.stakeholder_departments.join(', ')}
                    </Box>
                  )}
                  {!!contract.details.contact && (
                    <Box mt={0.5} bold>
                      Contact: {contract.details.contact} ·{' '}
                      {contract.details.contact_mode} ·{' '}
                      {contract.details.contact_share}% reward share
                    </Box>
                  )}
                  {!!contract.details.contact_cooperated && (
                    <Box mt={0.5} color="bad" bold>
                      The named contact withdrew the physical routing credential
                      and forfeited their faction settlement.
                    </Box>
                  )}
                  <Box mt={0.5} color="label">
                    Authenticated performers can collectively earn up to 25% of
                    the staff award; the remainder belongs to the agent after
                    the contact&apos;s negotiated cut.
                  </Box>
                  {!!contract.details.required_endorsements && (
                    <Box mt={0.5} color="label">
                      Physical head endorsements required:{' '}
                      {contract.details.required_endorsements}
                    </Box>
                  )}
                </Section>
              )}
              {contract.requirements.map((requirement) => (
                <Box key={`${contract.id}-${requirement.name}`} mb={1}>
                  <Box bold>
                    {requirement.name} — {requirement.progress_text}
                  </Box>
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
                  title={`Stakeholder participation — ${contract.details.stakeholder_summary}`}
                >
                  <Box mb={1} color="label">
                    Current graded specification: {contract.details.score}% ·{' '}
                    {contract.details.projected_grade} · projected award{' '}
                    {contract.details.projected_reward} Thalers
                  </Box>
                  <Box mb={1} color="label">
                    Share weights divide the fixed staff award. An appointment
                    qualifies after the stakeholder contributes attributable
                    work.
                  </Box>
                  {(contract.details.roles ?? []).map((role) => {
                    const ownProposal = role.proposals.find(
                      (proposal) => proposal.account === data.contract_account,
                    );
                    const canApply =
                      !!role.viewer_eligible &&
                      !role.viewer_has_other_role &&
                      ['active', 'grace'].includes(contract.state) &&
                      (!ownProposal ||
                        ['rejected', 'withdrawn', 'revoked'].includes(
                          ownProposal.status,
                        ));
                    return (
                      <Section
                        key={`${contract.id}-${role.id}`}
                        title={`${role.title} — ${role.qualified}/${role.minimum} qualified`}
                      >
                        <Box mb={0.5}>{role.description}</Box>
                        {ownProposal && (
                          <Box mb={0.5} color="label">
                            Your application: {ownProposal.status} · requested{' '}
                            {ownProposal.weight}×
                            {!!ownProposal.approved_weight &&
                              ` · offered ${ownProposal.approved_weight}×`}
                            {' · '}contribution {ownProposal.contribution}/
                            {role.minimum_contribution}
                            {ownProposal.qualified && ' · qualified'}
                          </Box>
                        )}
                        {ownProposal?.status === 'countered' && (
                          <Stack mb={0.5}>
                            <Stack.Item>
                              <Button
                                icon="check"
                                color="good"
                                onClick={() =>
                                  act('contract_stakeholder_respond', {
                                    id: contract.id,
                                    role: role.id,
                                    accepted: 1,
                                  })
                                }
                              >
                                Accept {ownProposal.approved_weight}× share
                              </Button>
                            </Stack.Item>
                            <Stack.Item>
                              <Button
                                icon="times"
                                onClick={() =>
                                  act('contract_stakeholder_respond', {
                                    id: contract.id,
                                    role: role.id,
                                    accepted: 0,
                                  })
                                }
                              >
                                Decline
                              </Button>
                            </Stack.Item>
                          </Stack>
                        )}
                        {ownProposal &&
                          ['pending', 'approved'].includes(
                            ownProposal.status,
                          ) && (
                            <Button
                              mb={0.5}
                              icon="user-minus"
                              onClick={() =>
                                act('contract_stakeholder_withdraw', {
                                  id: contract.id,
                                  role: role.id,
                                })
                              }
                            >
                              Withdraw
                            </Button>
                          )}
                        {canApply && (
                          <Stack>
                            {[1, 2, 3].map((weight) => (
                              <Stack.Item key={weight}>
                                <Button
                                  icon="handshake"
                                  onClick={() =>
                                    act('contract_stakeholder_propose', {
                                      id: contract.id,
                                      role: role.id,
                                      weight,
                                    })
                                  }
                                >
                                  {weight === 1
                                    ? 'Standard share'
                                    : weight === 2
                                      ? 'Major share'
                                      : 'Lead share'}
                                </Button>
                              </Stack.Item>
                            ))}
                          </Stack>
                        )}
                        {!!role.viewer_has_other_role && !ownProposal && (
                          <Box color="label">
                            You already hold or are seeking another role on this
                            contract.
                          </Box>
                        )}
                      </Section>
                    );
                  })}
                </Section>
              )}
            </Section>
          ))}
        </Box>
      )}
    </Box>
  );
};
