/// The mob's selected belly (where its vore goes), or null: a sparse link (LK_VORE_SELECTED), not a var on /mob.
/proc/vore_selected_of(mob/M) as /obj/belly
	return link_get(M, LK_VORE_SELECTED)

/// Selects belly B (one of M's vore_organs), or clears the selection with null.
/proc/set_vore_selected(mob/M, obj/belly/B)
	return link_set_one(M, LK_VORE_SELECTED, B)

/// The belly whose vore FX the mob is previewing in the vore panel, or null: a sparse link (LK_VORE_PREVIEW), not a var on /mob.
/proc/vore_previewing_of(mob/M) as /obj/belly
	return link_get(M, LK_VORE_PREVIEW)

/// Starts previewing belly B, or stops previewing with null.
/proc/set_vore_previewing(mob/M, obj/belly/B)
	return link_set_one(M, LK_VORE_PREVIEW, B)

/// The name of the belly the mob's vore goes to for `side` ("front", "rear", "left" or "right") when something is spontaneously eaten from there, or
/// null for the selected belly: a sparse text slot (spont_belly_<side>), not a var on /mob.
/proc/vore_spont_name(mob/M, side)
	var/spont_name
	switch(side)
		if("front")
			spont_name = "[sparse_get(M, spont_belly_front)]"
		if("rear")
			spont_name = "[sparse_get(M, spont_belly_rear)]"
		if("left")
			spont_name = "[sparse_get(M, spont_belly_left)]"
		if("right")
			spont_name = "[sparse_get(M, spont_belly_right)]"
	return spont_name || null

/mob
	var/list/vore_organs		// Lazy list of vore containers inside a mob
	var/absorbed = FALSE				// If a mob is absorbed into another

	// vore_capacity (maximum capacity, -1 for unlimited) and vore_capacity_ex (expanded list of capacities) are the living_rules type trait
	var/vore_fullness = 0				// How "full" the belly is (controls icons)
	// ALLOW(instance_list): d: per-mob vore_fullness_ex with starting entries, edited at runtime; mobs are few
	var/list/vore_fullness_ex = list("stomach" = 0) // Expanded list of fullness


	var/vore_icons = 0					// Bitfield for which fields we have vore icons for.

	var/obj/soulgem/soulgem				// Soulcatcher. Needs to be up-ported sometime.






// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
