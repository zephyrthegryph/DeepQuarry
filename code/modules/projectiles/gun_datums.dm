/*
 * Gun firemode selector datum.
 *
 *   /datum/gun_firemode_selector — firemode cycling and application.
 *
 * /obj/item/gun holds this as a nullable var member and delegates firemode
 * cycling/description to it.  The gun's `firemodes` list and `sel_mode` index
 * remain the source of truth; this datum is a thin API over them.
 *
 * NOTE: an earlier iteration of this file also defined /datum/gun_aim_state and
 * /datum/fire_context as part of a planned-but-abandoned decomposition of
 * /obj/item/gun.  They were never wired into the firing path — aim_state was
 * allocated per-gun but none of its sync/target methods were ever called,
 * fire_context was never instantiated, and the "_fire_one_shot" unification its
 * docstring described never existed.  Both have been removed.  The gun's own
 * aim_targets / last_moved_mob / told_cant_shoot / lock_time tmp vars remain the
 * live aiming state, read directly by the targeting overlay.
 */

// ---------------------------------------------------------------------------
// /datum/gun_firemode_selector
// ---------------------------------------------------------------------------

/// Manages the firemode list and the currently active mode.
/// Mirrors the firemodes list and sel_mode index on /obj/item/gun but provides
/// a cleaner API for switching and describing the selected mode.
/datum/gun_firemode_selector
	/// The gun that owns this selector.
	var/datum/weakref/gun_ref = null

/datum/gun_firemode_selector/New(obj/item/gun/gun)
	..()
	if(gun)
		gun_ref = WEAKREF(gun)

/datum/gun_firemode_selector/Destroy()
	gun_ref = null
	return ..()

/// Returns the currently active /datum/firemode, or null if no firemodes set.
/datum/gun_firemode_selector/proc/current_mode()
	var/obj/item/gun/gun = gun_ref?.resolve()
	if(!gun || !gun.firemodes.len)
		return null
	return gun.firemodes[gun.sel_mode]

/// Advance to the next mode (wrapping).  Applies the mode to the gun and
/// notifies user.  Returns the new mode or null if no change.
/datum/gun_firemode_selector/proc/cycle(mob/user)
	var/obj/item/gun/gun = gun_ref?.resolve()
	if(!gun || gun.firemodes.len <= 1)
		return null
	gun.sel_mode++
	if(gun.sel_mode > gun.firemodes.len)
		gun.sel_mode = 1
	var/datum/firemode/new_mode = gun.firemodes[gun.sel_mode]
	new_mode.apply_to(gun)
	if(user)
		to_chat(user, span_notice("\The [gun] is now set to [new_mode.name]."))
		user.hud_used.update_ammo_hud(user, gun)
	return new_mode

/// Description string for examine().
/datum/gun_firemode_selector/proc/describe()
	var/datum/firemode/mode = current_mode()
	if(!mode)
		return null
	return "The fire selector is set to [mode.name]."
