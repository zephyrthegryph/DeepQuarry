// Cargo's trade guides: visiting trade ships and the external market.

/datum/wiki_page/guide/cargo_trade_ships
	id = "guide/cargo/trade_ships"
	title = "Visiting trade ships"
	path = "Cargo/Guides"
	summary = "Ships that dock for a while, sell cheap, buy high and ship goods in to order."
	body = {"Every so often a trade ship enters the station's trade lane and stays docked for about fifteen minutes. Traffic Control announces each arrival and departure on the Supply channel. The Trade ships tab of a supply console lists the ships that are docked, how long each stays and the next expected arrival.

## What a ship offers
- Cargo for sale. A ship's stock appears on the Market tab beside the standing sellers, marked with the ship's name. It sells below the catalog price, cheaper still when the station stands well with the faction it trades for.
- Goods it wants. A ship's buy bids also appear on the Market tab. Route an outbound crate on the supply shuttle to one of them and it pays well above the spot price.
- Special orders. A ship will ship in any catalog pack from the groups it carries, for a markup over the catalog price. Search its special-order list and order on the department budget (approved like any order) or pay from your own account.

## Things to know
- A ship's listings and bids close when it leaves. Orders already placed keep their quoted price.
- The fixed market counterparties keep trading as before; ships trade alongside them.
- Each ship trades for one of the market's factions, so trading with it raises that faction's standing with the station and with Cargo.

## Standing and prices
Three kinds of standing set every trader's prices, for the fixed counterparties and the ships alike:
- Station: the station's standing with the trader's faction. Up to 6% either way.
- Department: Cargo's own standing with that faction, from the deals Cargo has made with it. Up to 5%.
- Trader: the trader's own regard for the station, earned deal by deal. Completed orders, filled bids, special orders and haggled sales raise it; insulting asks and haggling a ship into walking away lower it. Up to 4%.
Good standing makes what you buy (listings, special orders) cheaper and what you sell (bids, haggled crates) dearer; poor standing does the opposite. The Trade ships tab shows each layer for a ship, its tier and what it does to the price; the Market tab's Counterparties list shows the same for every trader. A ship's listings and bids are priced when it docks; special orders and haggling use your standing at that moment."}

/datum/wiki_page/guide/cargo_haggling
	id = "guide/cargo/haggling"
	title = "Haggling with trade ships"
	path = "Cargo/Guides"
	summary = "Appraise a crate as one lot, name your price, and take or push the ship's counteroffer."
	body = {"A docked \[\[guide/cargo/trade_ships|trade ship]] will buy whole crates straight off the supply shuttle at a price you negotiate. Use the Sell panel under the ship on the Trade ships tab of a Cargo supply console.

1. Load the crate onto the supply shuttle while it is at the station.
2. Appraise it. A crate is appraised as one lot: everything in it is valued together, not item by item. Your estimate can be wrong: anyone is off by up to 40%, Cargo staff by up to 20%. Appraising again gives you the same reading; a second person gives a second opinion.
3. Make an offer. The ship values the crate from what the spot market would pay for its contents, more for goods it wants (its buy bids on the Market tab), by the station's, Cargo's and its own standing (see \[\[guide/cargo/trade_ships|trade ships]]), and by its mood.

## How the ship answers
- At or under its valuation: it accepts, the crate ships at once and Cargo is paid. Department-made goods still pay their departments their usual share; the ship's extra is Cargo's premium. The trader thinks better of the station for it.
- Somewhat above: it counters. Take the counter, or ask again; each counter comes closer to the ship's own number.
- Far above: it rejects, its mood sours for every crate and its regard for the station drops.
- Each crate gets limited patience. Run it out and the ship stops negotiating for that crate, and thinks less of the station.
> Asking too little is accepted too. Appraise before you name a price."}

/datum/wiki_page/guide/cargo_black_market
	id = "guide/cargo/black_market"
	title = "Black-market ships"
	path = "Cargo/Guides"
	summary = "Dark freighters dealing arms and drugs off the books."
	body = {"Some ships dock without announcing themselves. They deal in weapons, restricted munitions and unlicensed drugs, sell contraband packs and pay very well for weapons and medical goods.

## Finding them
- A black-market ship appears on the Trade ships tab only of a supply console whose restrictions are lifted (an emagged or contraband-authorised console), or for an agent the ship's faction trusts. Its cargo and bids appear on the Market tab the same way.
- It trades under a cover name and leaves sooner than a lawful ship.
- Its prices follow the same three kinds of standing as any trader's.
- Black-market settlements leave encrypted records that a security auditor can trace (see \[\[guide/cargo/trade_ships|trade ships]])."}

/datum/wiki_page/guide/cargo_salvage
	id = "guide/cargo/salvage"
	title = "Salvage lots and recycling"
	path = "Cargo/Guides"
	summary = "Buy mystery lots, appraise and resell them, or break them down on the recycling line."
	body = {"The Supplies catalog sells unsorted lots: the Salvage lot (scrap electronics, parts and odds and ends) and the Surplus freight lot (boxes of whatever was in them, sundries and medicine). A lot is sold as seen: its manifest does not say what came, and every lot is different.

## Working a lot
- Appraise it. Keep the crate on the supply shuttle and appraise it at a Cargo supply console: the whole lot is valued together, with your own error (Cargo staff read freight better). See \[\[guide/cargo/haggling|haggling]].
- Resell it. Offer the crate to a docked trade ship, route it to a buy bid, or send it out on the shuttle at spot value.
- Pick through it. Keep what is useful, sell the rest.

## Breaking things down
Salvage goes through the station's ordinary recycling line:
- The recycling crusher breaks a thing and everything inside it (a box of scrap, a toolbox and its tools) into debris, keeping part of what it was made of. Upgraded parts keep more.
- The debris sorter collects debris until it has a sheet's worth of one material and hands out dust; the sheet stamper presses the dust into sheets.
- Nothing breaks down into more than it cost to make, and things with no recorded materials are refused (on a conveyor they pass out the side).
Sheets go to the lathes, or out on the shuttle: bulk materials are one of the things \[\[guide/cargo/trade_ships|visiting trade ships]] often want."}
