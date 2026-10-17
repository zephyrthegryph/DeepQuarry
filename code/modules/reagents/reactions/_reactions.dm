// Chemistry's transformations (doc/rewrite/proposals/transformations.md). A reaction is a type under /transformation/chem with a transformation(...) entry in
// its CAPABILITIES block, compiled once at world setup (code/library/transformations/) and settled by the reagent holders (/datum/reagents/proc/handle_reactions()).
//
// This block holds the defaults every reaction inherits; the families under it (instant, distilling) and the groups inside them (drinks, food, slime) hold their own,
// and each reaction names what it changes. What the rest of the entry's arguments mean is in code/library/transformations/transformation_entry.dm.
//
// Rates: rate = half_life(n) (half the reagents react after n chemistry ticks) or rate(r) (r of them each tick); a reaction with neither completes at once.

/transformation/chem

CAPABILITIES(/transformation/chem)
	transformation(regime = REGIME_INSTANT, says = "The solution begins to bubble.", plays = SFX_EFFECTS_BUBBLES)
