/*
 * Gun decomposition datums.
 *
 * Extracts cross-cutting concerns from /obj/item/gun into focused datums:
 *
 *   /datum/gun_aim_state      — per-shot aiming tracking (aim_targets, last_moved_mob, etc.)
 *   /datum/gun_firemode_selector — firemode cycling and application
 *   /datum/fire_context       — encapsulates per-fire-call context (user, target, params)
 *                               shared by handle_gunfire and handle_userless_gunfire
 *
 * /obj/item/gun holds these as nullable var members and delegates.  All existing
 * vars on the gun are KEPT for backwards compatibility — the datums mirror (not
 * replace) them.  Subtypes that set the vars directly continue to work unchanged.
 *
 * The fire_context datum unifies handle_gunfire / handle_userless_gunfire:
 * both now call the same _fire_one_shot() helper.  handle_userless_gunfire no
 * longer incorrectly recurses into handle_gunfire (which expected a user arg).
 */

// ---------------------------------------------------------------------------
// /datum/gun_aim_state
// ---------------------------------------------------------------------------

/// Tracks the transient aiming state of a gun between shots in a burst or
/// between aim-and-fire interactions.  Mirrors the tmp/ vars on /obj/item/gun.
/datum/gun_aim_state
	/// The gun this state belongs to.  Weakref to avoid blocking GC.
	var/datum/weakref/gun_ref = null

	/// Living mobs currently targeted by the aiming system.
	var/list/mob/living/aim_targets = null
	/// The last mob that moved during a tracked-aim sequence.
	var/mob/living/last_moved_mob = null
	/// Suppresses repeated "can't shoot" messages within the same aim session.
	var/told_cant_shoot = FALSE
	/// World.time stamp of when the aim lock was last acquired.
	var/lock_time = -100

/datum/gun_aim_state/New(obj/item/gun/gun)
	..()
	if(gun)
		gun_ref = WEAKREF(gun)

/datum/gun_aim_state/Destroy()
	aim_targets = null
	last_moved_mob = null
	gun_ref = null
	return ..()

/// Add a mob to the aim target list.
/datum/gun_aim_state/proc/add_target(mob/living/M)
	LAZYINITLIST(aim_targets)
	aim_targets |= M

/// Remove a mob from the aim target list.
/datum/gun_aim_state/proc/remove_target(mob/living/M)
	LAZYREMOVE(aim_targets, M)

/// Returns TRUE if the aim list contains this mob.
/datum/gun_aim_state/proc/has_target(mob/living/M)
	return M in aim_targets

/// Clear all tracking state (e.g. when aim is lowered or gun is dropped).
/datum/gun_aim_state/proc/clear()
	aim_targets    = null
	last_moved_mob = null
	told_cant_shoot = FALSE
	lock_time       = -100

/// Sync this datum's state back to the gun vars so legacy code that reads
/// gun.aim_targets / gun.last_moved_mob directly still sees correct values.
/datum/gun_aim_state/proc/sync_to_gun()
	var/obj/item/gun/gun = gun_ref?.resolve()
	if(!gun)
		return
	gun.aim_targets    = aim_targets
	gun.last_moved_mob = last_moved_mob
	gun.told_cant_shoot = told_cant_shoot ? 1 : 0
	gun.lock_time       = lock_time

/// Sync FROM the gun vars (used after legacy code may have mutated them).
/datum/gun_aim_state/proc/sync_from_gun()
	var/obj/item/gun/gun = gun_ref?.resolve()
	if(!gun)
		return
	aim_targets    = gun.aim_targets
	last_moved_mob = gun.last_moved_mob
	told_cant_shoot = gun.told_cant_shoot ? TRUE : FALSE
	lock_time       = gun.lock_time

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

// ---------------------------------------------------------------------------
// /datum/fire_context
// ---------------------------------------------------------------------------

/// Encapsulates a single fire-call's context: user (or null for userless),
/// target, click parameters, and flags.  Passed into the shared _fire_one_shot()
/// helper so that handle_gunfire and handle_userless_gunfire share one code path.
/datum/fire_context
	/// The mob pulling the trigger.  Null for autonomous/mounted guns.
	var/mob/living/user = null
	/// The atom being fired at.
	var/atom/target = null
	/// Raw click params string.
	var/params = null
	/// Whether this is a point-blank shot.
	var/pointblank = FALSE
	/// Whether this is a reflex shot.
	var/reflex = FALSE
	/// Current burst index (1-based).
	var/ticker = 1
	/// Whether this shot is part of a recursive burst (not the first shot).
	var/recursive = FALSE

/datum/fire_context/New(
	mob/living/user,
	atom/target,
	params = null,
	pointblank = FALSE,
	reflex = FALSE,
	ticker = 1,
	recursive = FALSE
)
	..()
	src.user      = user
	src.target    = target
	src.params    = params
	src.pointblank = pointblank
	src.reflex    = reflex
	src.ticker    = ticker
	src.recursive = recursive

/datum/fire_context/Destroy()
	user   = null
	target = null
	return ..()

/// Returns TRUE if a live user is present.
/datum/fire_context/proc/has_user()
	return (user && istype(user, /mob/living))

/// Apply click cooldown to the user.  No-op if no user.
/datum/fire_context/proc/apply_click_cooldown()
	if(has_user())
		user.setClickCooldown(DEFAULT_QUICK_COOLDOWN)

/// Apply movement cooldown to the user.  No-op if no user.
/datum/fire_context/proc/apply_move_delay(obj/item/gun/gun)
	if(!has_user() || !gun)
		return

// ---------------------------------------------------------------------------
// /datum/firemode extensions
// ---------------------------------------------------------------------------

/// Hook called when this firemode becomes the active mode on a gun.
/// Override in subtypes to apply custom initial state (e.g. UI notifications).
/datum/firemode/proc/on_apply(obj/item/gun/gun)
	return

/// Returns a short human-readable description for examine() and TGUI.
/datum/firemode/proc/on_describe()
	return name
