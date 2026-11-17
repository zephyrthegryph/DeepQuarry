#define CARGO_MARKET_REFRESH_INTERVAL (8 MINUTES)
#define CARGO_MARKET_LISTINGS_PER_PARTY 3
#define CARGO_MARKET_BIDS_PER_PARTY 3
#define CARGO_MARKET_TRANSACTION_LIMIT 100

#define CARGO_MARKET_BUY "station_purchase"
#define CARGO_MARKET_SELL "station_export"
#define CARGO_MARKET_FUNDING_DEPARTMENT "department"
#define CARGO_MARKET_FUNDING_PERSONAL "personal"
#define CARGO_MARKET_FUNDING_CONTRACT "contract"

#define CARGO_MARKET_AGENT_REPUTATION REPUTATION_ALLIED
#define CARGO_MARKET_AGENT_EARNED_REPUTATION 50
#define CARGO_MARKET_SYNDICATE_REPUTATION REPUTATION_UNFRIENDLY
#define CARGO_MARKET_SYNDICATE_EARNED_REPUTATION 20
#define CARGO_MARKET_AGENT_OFFERS 2
#define CARGO_MARKET_AGENT_OFFER_DELAY (2 MINUTES)

#define FACTION_AGENT_TIER_CANDIDATE 1
#define FACTION_AGENT_TIER_ACCREDITED 2
#define FACTION_AGENT_TIER_TRUSTED 3
#define FACTION_AGENT_TIER_OPERATIVE 4
#define FACTION_AGENT_TRUSTED_COMPLETIONS 3
#define FACTION_AGENT_TRUSTED_REPUTATION REPUTATION_ALLIED
#define FACTION_AGENT_MAX_EXPOSURE 100
#define FACTION_AGENT_INVESTIGATION_THRESHOLD 40
#define FACTION_AGENT_COUNTER_OFFER_THRESHOLD 30

#define CARGO_MARKET_LEGAL_PUBLIC "public"
#define CARGO_MARKET_LEGAL_RESTRICTED "restricted"
#define CARGO_MARKET_LEGAL_COVERT "covert"
#define CARGO_MARKET_TRACE_LIMIT 160
#define CARGO_MARKET_VETTING_VALUE 500

#define AGENT_CONTACT_STANDARD "standard"
#define AGENT_CONTACT_CONFIDENTIAL "confidential"
#define AGENT_CONTACT_DENIABLE "deniable"
#define AGENT_CONTACT_STANDARD_SHARE 35
#define AGENT_CONTACT_CONFIDENTIAL_SHARE 50
#define AGENT_CONTACT_DENIABLE_SHARE 65
#define AGENT_CONTACT_STANDARD_COMMISSION 0.05
#define AGENT_CONTACT_CONFIDENTIAL_COMMISSION 0.1
#define AGENT_CONTACT_DENIABLE_COMMISSION 0.15
#define AGENT_CONTACT_STANDARD_EXPOSURE 3
#define AGENT_CONTACT_CONFIDENTIAL_EXPOSURE 8
#define AGENT_CONTACT_DENIABLE_EXPOSURE 15
#define AGENT_INVESTIGATION_REPUTATION_PENALTY 20

#define CONTRACT_OPERATIVE_ANTAG_ID "contract_operative"

// Visiting trade ships (code/content/economy/trade_ships.dm).
#define TRADE_SHIP_FIRST_ARRIVAL (4 MINUTES)
#define TRADE_SHIP_MIN_INTERVAL (8 MINUTES)
#define TRADE_SHIP_MAX_INTERVAL (14 MINUTES)
#define TRADE_SHIP_MAX_DOCKED 2
#define TRADE_SHIP_ARRIVED "arrived"
#define TRADE_SHIP_DEPARTED "departed"

// Haggling with trade ships (code/content/economy/trade_offers.dm).
#define TRADE_OFFER_OPEN "open"
#define TRADE_OFFER_COUNTERED "countered"
#define TRADE_OFFER_WALKED "walked"
#define TRADE_OFFER_SETTLED "settled"
/// Rounds of haggling a ship sits through for one crate (a counter costs 1, a rejection 2).
#define TRADE_OFFER_PATIENCE 4
/// Asks up to this multiple of the ship's valuation draw a counteroffer; above it, a rejection.
#define TRADE_OFFER_COUNTER_CEILING 1.35
/// How much an insulting ask sours the ship's mood.
#define TRADE_OFFER_INSULT_MOOD 0.04
#define TRADE_SHIP_MOOD_MIN 0.7
#define TRADE_APPRAISAL_SPREAD_UNTRAINED 0.4
#define TRADE_APPRAISAL_SPREAD_TRAINED 0.2

// The three standing layers that set a trader's prices (trade_standing_layers(), cargo_market.dm). Each weight is the
// share a layer moves prices by at full standing (Revered or Hated); together at most 15%.
#define TRADE_STANDING_STATION "station"
#define TRADE_STANDING_DEPARTMENT "department"
#define TRADE_STANDING_TRADER "trader"
#define TRADE_STANDING_STATION_WEIGHT 0.06
#define TRADE_STANDING_DEPARTMENT_WEIGHT 0.05
#define TRADE_STANDING_TRADER_WEIGHT 0.04
/// How a trader's own regard moves: a completed purchase, a filled bid, a haggled sale or special order, an insulting ask,
/// and the trader walking away from a crate.
#define TRADE_TRADER_STANDING_PURCHASE 5
#define TRADE_TRADER_STANDING_BID 15
#define TRADE_TRADER_STANDING_SALE 10
#define TRADE_TRADER_STANDING_SPECIAL 5
#define TRADE_TRADER_STANDING_INSULT -10
#define TRADE_TRADER_STANDING_WALKED -25
