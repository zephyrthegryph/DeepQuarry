import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Input,
  LabeledList,
  NoticeBox,
  Section,
  Table,
} from 'tgui-core/components';
import type { SupplyConsoleActions } from '../generated/SupplyConsole';
import type { Data, TradeCrate, TradeShip } from './types';

const percent = (rate: number) => `${Math.round(rate * 100)}%`;

const SpecialOrders = (props: { ship: TradeShip }) => {
  const { act } = useBackend<Data, SupplyConsoleActions>();
  const { ship } = props;
  const [search, setSearch] = useState('');
  const needle = search.toLowerCase();
  const specials = ship.specials.filter(
    (special) =>
      !needle ||
      special.name.toLowerCase().includes(needle) ||
      special.group.toLowerCase().includes(needle),
  );
  return (
    <Section title="Special orders">
      <Input
        fluid
        placeholder="Search goods this ship will ship in..."
        value={search}
        onChange={(value) => setSearch(value)}
      />
      <Table mt={0.5}>
        <Table.Row header>
          <Table.Cell>Goods</Table.Cell>
          <Table.Cell>Group</Table.Cell>
          <Table.Cell collapsing>Catalog</Table.Cell>
          <Table.Cell collapsing>Ship price</Table.Cell>
          <Table.Cell collapsing />
        </Table.Row>
        {specials.map((special) => (
          <Table.Row key={special.name}>
            <Table.Cell color={special.contraband ? 'bad' : undefined}>
              {special.name}
              {special.contraband ? ' (restricted)' : ''}
            </Table.Cell>
            <Table.Cell>{special.group}</Table.Cell>
            <Table.Cell collapsing>{special.catalog}₮</Table.Cell>
            <Table.Cell collapsing bold>
              {special.price}₮
            </Table.Cell>
            <Table.Cell collapsing>
              <Button
                icon="building"
                disabled={!ship.can_department}
                tooltip="Request on the department budget"
                onClick={() =>
                  act('special_order', {
                    ship: ship.id,
                    pack: special.name,
                    personal: false,
                  })
                }
              />
              <Button
                icon="wallet"
                disabled={!ship.can_personal}
                tooltip="Pay from your own account"
                onClick={() =>
                  act('special_order', {
                    ship: ship.id,
                    pack: special.name,
                    personal: true,
                  })
                }
              />
            </Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

const statusColor = {
  open: 'average',
  countered: 'good',
  walked: 'bad',
  settled: 'label',
};

const Haggling = (props: { ship: TradeShip; crates: TradeCrate[] }) => {
  const { act, data } = useBackend<Data, SupplyConsoleActions>();
  const { ship, crates } = props;
  const canTrade = !!data.market_auth;
  return (
    <Section title={`Sell to ${ship.name} · mood: ${ship.mood}`}>
      {!canTrade && (
        <NoticeBox info>
          A Cargo control console and Cargo access are needed to haggle.
        </NoticeBox>
      )}
      {!crates.length && (
        <Box color="label">
          Load a crate onto the supply shuttle to offer it to this ship.
        </Box>
      )}
      <Table>
        {crates.map((crate) => {
          const offer = ship.offers.find(
            (candidate) =>
              candidate.crate_ref === crate.ref &&
              candidate.status !== 'settled',
          );
          return (
            <Table.Row key={crate.ref}>
              <Table.Cell>
                {crate.name} ({crate.contents} items)
              </Table.Cell>
              <Table.Cell>
                {crate.appraiser
                  ? `~${crate.appraisal}₮ ±${crate.spread}% (${crate.appraiser})`
                  : 'Not appraised'}
              </Table.Cell>
              <Table.Cell>
                {offer && (
                  <Box color={statusColor[offer.status]}>
                    Asked {offer.ask}₮ · {offer.reply}
                    {offer.status !== 'walked' &&
                      ` · patience ${offer.patience}`}
                  </Box>
                )}
              </Table.Cell>
              <Table.Cell collapsing>
                <Button
                  icon="magnifying-glass-dollar"
                  disabled={!canTrade}
                  tooltip="Appraise the crate (an appraiser in hand helps)"
                  onClick={() => act('trade_appraise', { crate: crate.ref })}
                />
                <Button
                  icon="comments-dollar"
                  disabled={!canTrade || offer?.status === 'walked'}
                  onClick={() =>
                    act('trade_offer', { ship: ship.id, crate: crate.ref })
                  }
                >
                  Offer
                </Button>
                {offer?.status === 'countered' && (
                  <Button
                    icon="handshake"
                    color="good"
                    disabled={!canTrade}
                    onClick={() =>
                      act('trade_accept', { ship: ship.id, offer: offer.id })
                    }
                  >
                    Take {offer.counter}₮
                  </Button>
                )}
              </Table.Cell>
            </Table.Row>
          );
        })}
      </Table>
      {ship.offers
        .filter((offer) => offer.status === 'settled')
        .map((offer) => (
          <Box key={offer.id} color="good">
            Sold {offer.crate} for {offer.price}₮ ({offer.offered_by})
          </Box>
        ))}
    </Section>
  );
};

export const SupplyConsoleTradeShips = () => {
  const { data } = useBackend<Data, SupplyConsoleActions>();
  const traffic = data.market?.trade_ships;
  if (!traffic) {
    return <NoticeBox danger>Trade lane traffic is unavailable.</NoticeBox>;
  }
  return (
    <Section fill scrollable>
      <NoticeBox info>
        Visiting ships trade at better rates than the standing market. Their
        cargo and wanted goods appear on the Market tab while they are docked.
        Next arrival expected in {traffic.next_ship}.
      </NoticeBox>
      {!traffic.ships.length && (
        <NoticeBox>No trade ships are docked.</NoticeBox>
      )}
      {traffic.ships.map((ship) => (
        <Section key={ship.id} title={ship.name}>
          <Box mb={0.5}>{ship.description}</Box>
          {!!ship.covert && (
            <NoticeBox danger>
              Off-the-books dealer. Customs watches these lanes: each deal has
              about a {ship.heat}% chance of being caught, rising with every
              deal. A caught deal is reported to Security under the paying
              account holder and costs NanoTrasen standing.
            </NoticeBox>
          )}
          <LabeledList>
            <LabeledList.Item label="Trading for">
              {ship.counterparty} · {ship.standing_tier} ({ship.standing})
            </LabeledList.Item>
            <LabeledList.Item label="Departs in">
              {ship.departs}
            </LabeledList.Item>
            <LabeledList.Item label="Rates">
              sells at {percent(ship.sell_rate)} of catalog · buys wanted goods
              at ×{ship.buy_rate.toFixed(2)} · special orders ×
              {ship.special_markup.toFixed(2)}
            </LabeledList.Item>
          </LabeledList>
          <Haggling ship={ship} crates={traffic.crates} />
          <SpecialOrders ship={ship} />
        </Section>
      ))}
    </Section>
  );
};
