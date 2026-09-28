// Contains old mediciation, most of it unidentified and has a good chance of being useless.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/datum/loot_table/expired_medicine
	chance_uncommon = 0
	chance_rare = 0
	common_loot = list(
		/obj/random/unidentified_medicine/old_medicine
	)

// Like the above but has way better odds, in exchange for being in a place still inhabited (or was recently).
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/datum/loot_table/fresh_medicine
	chance_uncommon = 0
	chance_rare = 0
	common_loot = list(
		/obj/random/unidentified_medicine/fresh_medicine
	)
