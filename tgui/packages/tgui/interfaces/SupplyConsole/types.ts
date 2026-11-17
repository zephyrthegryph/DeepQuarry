import type { BooleanLike } from 'tgui-core/react';

export type Data = {
  shuttle_auth: BooleanLike;
  order_auth: BooleanLike;
  shuttle: ShuttleStatus;
  supply_points: number;
  personal_balance: number;
  can_personal_order: BooleanLike;
  orders: Order[];
  receipts: Receipt[];
  contraband: BooleanLike;
  market_auth: BooleanLike;
  market: CargoMarket;
  modal: ModalData;
  supply_packs: SupplyPack[];
  categories: string[];
};

export type CargoMarketCounterparty = {
  id: string;
  name: string;
  description: string;
  faction: string;
  color: string;
  standing: number;
  standing_tier: string;
  covert: BooleanLike;
};

export type CargoMarketListing = {
  id: string;
  counterparty_id: string;
  counterparty: string;
  name: string;
  description: string;
  group: string;
  price: number;
  stock: number;
  contraband: BooleanLike;
  reserved: BooleanLike;
  can_department: BooleanLike;
  can_personal: BooleanLike;
  can_contract: BooleanLike;
  contract_allowance: number;
  expires: string;
  ship?: string;
};

export type CargoMarketBid = {
  id: string;
  counterparty_id: string;
  counterparty: string;
  name: string;
  description: string;
  fulfilled: number;
  target: number;
  remaining: number;
  multiplier: number;
  reserved: BooleanLike;
  can_route: BooleanLike;
  expires: string;
  ship?: string;
};

export type CargoMarketTransaction = {
  id: string;
  type: string;
  counterparty: string;
  description: string;
  value: number;
  time: string;
  covert: BooleanLike;
  auditable: BooleanLike;
  detected: BooleanLike;
  suspect?: string;
  trace: number;
};

export type CargoMarketCrate = {
  ref: number;
  name: string;
  contents: number;
  bid_id?: string;
  route: string;
};

export type CargoMarket = {
  generation: number;
  refresh_in: string;
  counterparties: CargoMarketCounterparty[];
  listings: CargoMarketListing[];
  bids: CargoMarketBid[];
  transactions: CargoMarketTransaction[];
  outbound_crates: CargoMarketCrate[];
  is_auditor: BooleanLike;
  trade_ships: TradeShips;
};

export type TradeShipSpecial = {
  name: string;
  group: string;
  price: number;
  catalog: number;
  contraband: BooleanLike;
};

export type TradeShip = {
  id: string;
  name: string;
  description: string;
  counterparty: string;
  covert: BooleanLike;
  heat: number;
  standing: number;
  standing_tier: string;
  departs: string;
  sell_rate: number;
  buy_rate: number;
  special_markup: number;
  specials: TradeShipSpecial[];
  mood: string;
  offers: TradeOffer[];
  can_department: BooleanLike;
  can_personal: BooleanLike;
};

export type TradeOffer = {
  id: string;
  crate: string;
  crate_ref?: string;
  offered_by: string;
  ask: number;
  counter: number;
  status: 'open' | 'countered' | 'walked' | 'settled';
  patience: number;
  reply: string;
  price: number;
};

export type TradeCrate = {
  ref: string;
  name: string;
  contents: number;
  appraisal: number;
  spread: number;
  appraiser?: string;
};

export type TradeShips = {
  ships: TradeShip[];
  crates: TradeCrate[];
  next_ship: string;
};

export type ModalData = {
  id: string;
  text: string;
  args: {
    name: string;
    desc: string;
    cost: number;
    manifest: string[];
    ref: number;
    random: number;
  };
  type: string;
};

export type SupplyPack = {
  name: string;
  desc: string;
  cost: number;
  group: string;
  contraband: BooleanLike;
  manifest: string[];
  random: number;
  ref: number;
};

type ShuttleStatus = {
  location: string;
  mode: number;
  time: number;
  launch: number;
  engine: string;
  force: BooleanLike;
};

type Order = {
  ref: number;
  status: string;
  cost: number;
  can_approve: BooleanLike;
  entries: { field: string; entry: string }[];
};

type Receipt = {
  ref: number;
  contents: {
    object: string;
    quantity: number;
    value: number;
    error: string | undefined;
  }[];
  error: string | undefined;
  title: { field: string; entry: string }[];
};
