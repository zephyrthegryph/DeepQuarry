/*
 * /datum/magazine_appearance — ammo-count icon-state manager for magazines.
 *
 * Consolidates the multiple_sprites / icon_keys / ammo_states system behind a
 * single datum.  The magazine holds one nullable reference; update_icon() calls
 * datum.apply_icon(src) to pick the correct icon_state from a cached table.
 *
 * The existing proc-level cache (magazine_icondata_keys / magazine_icondata_states
 * in GLOB) is preserved for backwards compatibility; this datum just wraps the
 * same logic behind a cleaner API.
 *
 * Usage in /obj/item/ammo_magazine subtypes that need multiple_sprites:
 *   /obj/item/ammo_magazine/m45
 *       multiple_sprites = 1   // existing flag; triggers initialize_magazine_icondata()
 *
 * There is nothing new to wire for existing magazines — the datum is used
 * transparently through the existing update_icon() override.  New magazines can
 * also instantiate a datum directly for more control:
 *
 *   /obj/item/ammo_magazine/my_mag
 *       var/datum/magazine_appearance/appearance = null
 *
 *   /obj/item/ammo_magazine/my_mag/Initialize(mapload)
 *       . = ..()
 *       appearance = new(src)
 *
 *   /obj/item/ammo_magazine/my_mag/update_icon()
 *       if(appearance)
 *           appearance.apply_icon(src)
 *       else
 *           ..()
 */

/datum/magazine_appearance
	/// Icon file to scan for ammo-count states.
	var/icon_file = null
	/// Base icon_state prefix (e.g. "45" for "45-0", "45-1", "45-7").
	var/base_state = null
	/// Maximum ammo count (determines the icon-state range scanned at init).
	var/max_ammo = 0

	/// Flat list of ammo thresholds (ascending).  Parallel to state_names.
	var/list/thresholds = list()
	/// Icon states corresponding to each threshold.
	var/list/state_names = list()

/datum/magazine_appearance/New(obj/item/ammo_magazine/mag)
	..()
	if(!mag)
		return
	icon_file  = mag.icon
	base_state = mag.icon_state
	max_ammo   = mag.max_ammo
	_build_cache(mag)

/datum/magazine_appearance/Destroy()
	thresholds = null
	state_names = null
	return ..()

/// Scan the icon file for states of the form "[base_state]-[N]" (N = 0..max_ammo)
/// and build the threshold/state_names parallel lists.  Caches results in GLOB
/// so subsequent magazines of the same type skip the scan.
/datum/magazine_appearance/proc/_build_cache(obj/item/ammo_magazine/mag)
	var/typestr = mag.type
	if((typestr in GLOB.magazine_icondata_keys) && (typestr in GLOB.magazine_icondata_states))
		// Already cached globally; re-use.
		thresholds  = GLOB.magazine_icondata_keys[typestr]
		state_names = GLOB.magazine_icondata_states[typestr]
		return

	// Build from scratch.
	var/list/built_keys   = list()
	var/list/built_states = list()
	var/list/states       = icon_states_fast(icon_file)
	for(var/i = 0, i <= max_ammo, i++)
		var/candidate = "[base_state]-[i]"
		if(candidate in states)
			built_keys   += i
			built_states += candidate

	GLOB.magazine_icondata_keys[typestr]   = built_keys
	GLOB.magazine_icondata_states[typestr] = built_states
	thresholds  = built_keys
	state_names = built_states

/// Apply the correct icon_state to the magazine based on its current ammo count.
/// Selects the lowest threshold >= stored_ammo.len.
/datum/magazine_appearance/proc/apply_icon(obj/item/ammo_magazine/mag)
	if(!mag || !thresholds.len)
		return
	var/new_state = null
	for(var/idx in 1 to thresholds.len)
		var/threshold = thresholds[idx]
		if(threshold >= mag.stored_ammo.len)
			new_state = state_names[idx]
			break
	mag.icon_state = (new_state) ? new_state : initial(mag.icon_state)
