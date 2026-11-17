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
import type { Data, TradeShip } from './types';

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
            <Table.Cell>{special.name}</Table.Cell>
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
          <SpecialOrders ship={ship} />
        </Section>
      ))}
    </Section>
  );
};
