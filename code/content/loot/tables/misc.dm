// Searchable loot tables (loot_search(), code/datums/loot/loot.dm). Each declaration is complete:
// it carries every tier and setting it had, inherited ones included.

// Contains old mediciation, most of it unidentified and has a good chance of being useless.
CAPABILITIES(/loot/expired_medicine)
	loot(table = list(/obj/random/unidentified_medicine/old_medicine))

// Like the above but has way better odds, in exchange for being in a place still inhabited (or was recently).
CAPABILITIES(/loot/fresh_medicine)
	loot(table = list(/obj/random/unidentified_medicine/fresh_medicine))
