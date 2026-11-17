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
- Each ship trades for one of the market's factions, so trading with it raises that faction's standing with the station and with Cargo."}

/datum/wiki_page/guide/cargo_haggling
	id = "guide/cargo/haggling"
	title = "Haggling with trade ships"
	path = "Cargo/Guides"
	summary = "Appraise a crate, name your price, and take or push the ship's counteroffer."
	body = {"A docked \[\[guide/cargo/trade_ships|trade ship]] will buy whole crates straight off the supply shuttle at a price you negotiate. Use the Sell panel under the ship on the Trade ships tab of a Cargo supply console.

1. Load the crate onto the supply shuttle while it is at the station.
2. Appraise it. Your estimate can be wrong: anyone is off by up to 40%, Cargo staff by up to 20%, and holding a cargo appraiser (orderable as the Cargo appraiser crate) cuts the error to about a third. Appraising again gives you the same reading; a second person gives a second opinion.
3. Make an offer. The ship values the crate from what the spot market would pay for its contents, more for goods it wants (its buy bids on the Market tab), more again when the station stands well with its faction, and by its mood.

## How the ship answers
- At or under its valuation: it accepts, the crate ships at once and Cargo is paid. Department-made goods still pay their departments their usual share; the ship's extra is Cargo's premium.
- Somewhat above: it counters. Take the counter, or ask again; each counter comes closer to the ship's own number.
- Far above: it rejects, and its mood sours for every crate.
- Each crate gets limited patience. Run it out and the ship stops negotiating for that crate.
> Asking too little is accepted too. Appraise before you name a price."}

/datum/wiki_page/guide/cargo_black_market
	id = "guide/cargo/black_market"
	title = "Black-market ships"
	path = "Cargo/Guides"
	summary = "Dark freighters dealing arms and drugs, and the customs risk of dealing with them."
	body = {"Some ships dock without announcing themselves. They deal in weapons, restricted munitions and unlicensed drugs, sell contraband packs and pay very well for weapons and medical goods.

## Finding them
- A black-market ship appears on the Trade ships tab only of a supply console whose restrictions are lifted (an emagged or contraband-authorised console), or for an agent the ship's faction trusts. Its cargo and bids appear on the Market tab the same way.
- It trades under a cover name and leaves sooner than a lawful ship.

## The risk
- Customs watches the lanes. Every deal (a purchase, a special order, a haggled sale) may be caught. The ship's panel shows the current chance, which rises with every deal struck during its stay.
- A caught deal is reported to Security on the Security channel, naming the paying account holder. The station, Cargo and the dealer lose standing with NanoTrasen, and the dealer's exposure to investigators rises.
- Even uncaught, black-market settlements leave encrypted records that a security auditor can trace (see \[\[guide/cargo/trade_ships|trade ships]])."}
