import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Collapsible,
  Dropdown,
  LabeledList,
  NoticeBox,
  ProgressBar,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';

import type { CargoMarketBid, Data } from './types';

const bidLabel = (bid: CargoMarketBid) =>
  `${bid.counterparty} — ${bid.name} (×${bid.multiplier.toFixed(2)})`;

export const SupplyConsoleMarket = () => {
  const { act, data } = useBackend<Data>();
  const market = data.market;
  const routeOptions = [
    'Spot market',
    ...(market?.bids ?? [])
      .filter((bid) => bid.can_route)
      .map((bid) => bidLabel(bid)),
  ];

  if (!market) {
    return (
      <NoticeBox danger>The external market feed is unavailable.</NoticeBox>
    );
  }

  return (
    <Stack vertical fill>
      <Stack.Item>
        <Section>
          <NoticeBox>
            Market cycle #{market.generation} · quotes refresh in{' '}
            {market.refresh_in}. Contract-reserved routes survive ordinary
            refreshes. Personal orders debit your account; department requests
            follow the normal approval workflow.
          </NoticeBox>
        </Section>
      </Stack.Item>
      <Stack.Item grow>
        <Stack fill>
          <Stack.Item basis="50%">
            <Section fill scrollable title="External sellers">
              {!market.listings.length && (
                <Box color="label">No seller listings are available.</Box>
              )}
              {market.listings.map((listing) => (
                <Section
                  key={listing.id}
                  title={listing.name}
                  buttons={
                    <Stack>
                      <Stack.Item>
                        <Button
                          icon="building"
                          disabled={!listing.can_department}
                          onClick={() =>
                            act('market_request', {
                              id: listing.id,
                              personal: false,
                            })
                          }
                        >
                          Department · {listing.price}₮
                        </Button>
                      </Stack.Item>
                      <Stack.Item>
                        <Button
                          icon="wallet"
                          disabled={!listing.can_personal}
                          onClick={() =>
                            act('market_request', {
                              id: listing.id,
                              personal: true,
                            })
                          }
                        >
                          Personal · {listing.price}₮
                        </Button>
                      </Stack.Item>
                      {!!listing.can_contract && (
                        <Stack.Item>
                          <Button
                            icon="file-contract"
                            color="average"
                            onClick={() =>
                              act('market_request', {
                                id: listing.id,
                                contract: true,
                              })
                            }
                          >
                            Contract · {listing.price}₮
                          </Button>
                        </Stack.Item>
                      )}
                    </Stack>
                  }
                >
                  <Box color="label">
                    {listing.counterparty} · {listing.group} · {listing.stock}{' '}
                    in stock · {listing.expires}
                  </Box>
                  {!!listing.contraband && (
                    <Box color="bad" bold>
                      Restricted listing
                    </Box>
                  )}
                  {!!listing.reserved && (
                    <Box color="average" bold>
                      Reserved contract route
                      {!!listing.can_contract &&
                        ` · ${listing.contract_allowance}₮ sponsor allowance remaining`}
                    </Box>
                  )}
                  <Box>{listing.description}</Box>
                </Section>
              ))}
            </Section>
          </Stack.Item>
          <Stack.Item basis="50%">
            <Section fill scrollable title="External buyers">
              {!market.bids.length && (
                <Box color="label">No active purchase bids are available.</Box>
              )}
              {market.bids.map((bid) => (
                <Section key={bid.id} title={bid.name}>
                  <Box color="label">
                    {bid.counterparty} · pays ×{bid.multiplier.toFixed(2)} ·{' '}
                    {bid.expires}
                  </Box>
                  <Box mb={0.5}>{bid.description}</Box>
                  <ProgressBar value={bid.fulfilled} maxValue={bid.target}>
                    {bid.fulfilled} / {bid.target} units
                  </ProgressBar>
                  {!!bid.reserved && (
                    <Box color="average">
                      Reserved contract route · place its signed physical
                      freight agreement inside the outbound crate to
                      authenticate it
                    </Box>
                  )}
                </Section>
              ))}
            </Section>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        <Collapsible title="Outbound crate routing" open>
          {!data.market_auth && (
            <NoticeBox info>
              A Cargo control console is required to alter shipment routes.
            </NoticeBox>
          )}
          {!market.outbound_crates.length && (
            <Box color="label">
              No movable crates are on the supply shuttle.
            </Box>
          )}
          {market.outbound_crates.map((crate) => (
            <LabeledList key={crate.ref}>
              <LabeledList.Item
                label={`${crate.name} (${crate.contents} contents)`}
              >
                <Dropdown
                  disabled={
                    !data.market_auth &&
                    !market.bids.some((bid) => bid.can_route)
                  }
                  options={routeOptions}
                  selected={crate.route}
                  width="100%"
                  onSelected={(selection) => {
                    const bid = market.bids.find(
                      (candidate) => bidLabel(candidate) === selection,
                    );
                    act('market_route', {
                      crate: crate.ref,
                      bid: bid?.id,
                    });
                  }}
                />
              </LabeledList.Item>
            </LabeledList>
          ))}
        </Collapsible>
      </Stack.Item>
      <Stack.Item>
        <Collapsible title="Counterparties and standing">
          <Table>
            {market.counterparties.map((party) => (
              <Table.Row
                key={party.id}
                style={{ borderLeft: `4px solid ${party.color}` }}
              >
                <Table.Cell bold>{party.name}</Table.Cell>
                <Table.Cell>{party.faction}</Table.Cell>
                <Table.Cell>
                  {party.standing_tier} ({party.standing})
                </Table.Cell>
                <Table.Cell>{party.description}</Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Collapsible>
        <Collapsible title="Recent market settlements">
          {!market.transactions.length && (
            <Box color="label">No market trades have settled this cycle.</Box>
          )}
          {market.transactions.map((transaction, index) => (
            <Section
              key={transaction.id || `${transaction.time}-${index}`}
              mb={0.5}
              title={`${transaction.time} · ${transaction.counterparty}`}
            >
              {transaction.description} · {transaction.value}₮
              {!!transaction.covert && !!market.is_auditor && (
                <Box color={transaction.detected ? 'bad' : 'average'}>
                  Encrypted settlement metadata is present. Use a forensic
                  scanner on the physical Supply Console to recover the next
                  cached lead.
                  {transaction.detected
                    ? ` · identity correlation: ${transaction.suspect}`
                    : ''}
                </Box>
              )}
            </Section>
          ))}
        </Collapsible>
      </Stack.Item>
    </Stack>
  );
};
