/// The mob's selected belly (where its vore goes), or null: a sparse link (LK_VORE_SELECTED), not a var on /mob.
/proc/vore_selected_of(mob/M) as /obj/belly
	return link_get(M, LK_VORE_SELECTED)

/// Selects belly B (one of M's vore_organs), or clears the selection with null.
/proc/set_vore_selected(mob/M, obj/belly/B)
	return link_set_one(M, LK_VORE_SELECTED, B)

/mob
	var/list/vore_organs		// Lazy list of vore containers inside a mob
	var/absorbed = FALSE				// If a mob is absorbed into another
	var/obj/belly/spont_belly_front = null
	var/obj/belly/spont_belly_rear = null
	var/obj/belly/spont_belly_left = null
	var/obj/belly/spont_belly_right = null

	var/vore_capacity = 0				// Maximum capacity, -1 for unlimited
	var/vore_capacity_ex = list("stomach" = 0) //expanded list of capacities
	var/vore_fullness = 0				// How "full" the belly is (controls icons)
	// ALLOW(instance_list): d: per-mob vore_fullness_ex with starting entries, edited at runtime; mobs are few
	var/list/vore_fullness_ex = list("stomach" = 0) // Expanded list of fullness
	var/belly_size_multiplier = 1

	var/list/vore_icon_bellies = list("stomach") // ALLOW(instance_list): d: per-mob vore_icon_bellies with starting entries, edited at runtime; mobs are few
	var/updating_fullness = FALSE
	var/tmp/obj/belly/previewing_belly

	var/vore_icons = 0					// Bitfield for which fields we have vore icons for.
	var/vore_eyes = FALSE				// For mobs with fullness specific eye overlays.

	var/obj/soulgem/soulgem				// Soulcatcher. Needs to be up-ported sometime.


	// ALLOW(instance_list): d: per-mob voice_sounds_list, filled at runtime; mobs are few
	var/list/voice_sounds_list = list()	// The sound list containing our voice sounds!
	var/died_in_vr = FALSE //For virtual reality sleepers
	EXPIRY_DECLARE(last_move_time) //For movement smoothing




// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
