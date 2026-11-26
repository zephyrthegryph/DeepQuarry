// Cargo lots: mystery freight sold as supply packs (`lot_table =` on a /datum/supply_pack, delivered by
// SSsupply's shipment code). Each lot is a pure table of existing items and tables, rolled `count` times into
// the crate. The manifest does not list a lot's contents: what it is worth is found by appraising the crate as
// one lot at a supply console (trade_offers.dm), then reselling it or breaking it down for salvage.

// Scrap electronics, parts and odds and ends from decommissioned stations.
CAPABILITIES(/loot/cargo_lot/salvage)
	loot(
		table = list(
			/loot/maint/technical = 3,
			/loot/maint/junk = 2),
		count = 6)

// Unclaimed general freight: boxes of whatever was in them, sundries and medicine.
CAPABILITIES(/loot/cargo_lot/surplus)
	loot(
		table = list(
			/loot/boxes = 3,
			/loot/maint/junk = 2,
			/loot/fresh_medicine = 1),
		count = 5)
