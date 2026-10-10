/*
 * True autofire (hold-to-fire).
 *
 * A gun with `automatic = 1` sustains fire while the left mouse button is held
 * over a target: the existing Fire() path is re-pulled at the gun's fire_delay
 * cadence until the button is released, the target is lost, the gun leaves the
 * active hand, the user dies, or the gun runs dry.
 *
 * Design notes:
 *   - This drives the *existing* fire path; it adds no new shooting logic.  Each
 *     trigger pull respects the gun's current firemode (a 3-round-burst gun
 *     fires repeated bursts; a semi-auto-only gun fires repeated single shots).
 *   - Cadence is gated on gun.next_fire_time, which Fire()/handle_gunfire already
 *     set correctly for both single shots and bursts, so the loop needs no
 *     knowledge of burst internals.
 *   - The loop is timer-driven (no long-lived sleeping proc) so it is cheap and
 *     trivially cancellable.
 *   - Mouse capture is at /client level so it works over turfs, objs and mobs.
 *     HUD (screen) clicks and non-left buttons are ignored; ..() is always
 *     called so normal clicking, examine, drag-drop etc. are untouched.
 *   - Empty guns stop the loop via /obj/item/gun/handle_click_empty (see gun.dm),
 *     so a dry magazine yields a single click rather than a stream.
 */

// ---------------------------------------------------------------------------
// Per-mob autofire state + loop
// ---------------------------------------------------------------------------

/mob/living
	/// Wait before the next autofire_tick(), set by each tick from the gun's cadence.
	var/tmp/autofire_delay = 0
	var/tmp/obj/item/gun/autofire_gun
	var/tmp/atom/autofire_target
	var/tmp/autofire_params = null

/// TRUE while a hold-to-fire session runs: autofire_tick() repeats every autofire_delay (its every() in CAPABILITIES(/mob/living)).
/mob/living/var/tmp/autofire_on = FALSE // ALLOW(base_vars): was an OM_FIELD on this type; moved, not added
TRACKED(/mob/living, autofire_on)

/// The every() interval of autofire_tick(): the wait the last tick set.
/mob/living/proc/autofire_interval(datum/act/A)
	return autofire_delay

/// Begin (or retarget) a held-trigger autofire session with gun G at target.
/mob/living/proc/start_autofire(obj/item/gun/G, atom/target, params)
	if(QDELETED(G) || QDELETED(target))
		return
	rel_set(src, nameof(autofire_gun), G)
	rel_set(src, nameof(autofire_target), target)
	autofire_params = params
	if(!autofire_on)
		autofire_delay = 0 // the first trigger pull comes right away
		set_autofire_on(TRUE)

/// Update the target/params of an in-progress session (mouse dragged onto a new
/// tile while the button is still held).  No-op if not autofiring.
/mob/living/proc/update_autofire_target(atom/target, params)
	if(autofire_on && !QDELETED(target))
		rel_set(src, nameof(autofire_target), target)
		autofire_params = params

/// End any autofire session and clear all held state.  Safe to call when idle.
/mob/living/proc/stop_autofire()
	set_autofire_on(FALSE)
	rel_clear(src, nameof(autofire_gun))
	rel_clear(src, nameof(autofire_target))
	autofire_params = null

/// One iteration of the hold-to-fire loop (declared: while autofire_on).  Fires if the gun is
/// ready and sets the wait before the next one; a stop condition ends the session.
/mob/living/proc/autofire_tick(datum/act/A)
	var/obj/item/gun/G = autofire_gun()
	var/atom/target = autofire_target()
	// Stop conditions: gun gone / not in hand / no longer automatic / KO'd or
	// dead / target gone.
	if(QDELETED(src) || stat || QDELETED(G) || !G.automatic \
			|| get_active_hand() != G || QDELETED(target))
		stop_autofire()
		return

	var/delay
	if(COOLDOWN_FINISHED(G, next_fire_time))
		G.Fire(target, src, autofire_params)
		// Re-check: Fire()/handle_click_empty may have ended the session
		// (dropped gun, ran dry) this tick.
		if(!autofire_on)
			return
		delay = max(1, G.fire_delay)
	else
		// Not ready yet (mid-burst or cooling down): wait exactly until it is.
		delay = max(1, G.next_fire_time - world.time)

	autofire_delay = delay

// ---------------------------------------------------------------------------
// Client mouse capture
// ---------------------------------------------------------------------------

/// TRUE if this mouse event is a plain left-click on the game map (not a HUD
/// screen object, not a right/middle click).
/client/proc/autofire_is_map_left_click(atom/object, params)
	if(istype(object, /atom/movable/screen))	// HUD element, not the world
		return FALSE
	if(!isatom(object))
		return FALSE
	var/list/pa = params2list(params)
	if(GLOB.input_router.click_is(pa, TYPE_TABLE_GET(GLOB.input_router, secondary_table), INPUT_ACTION_ALTERNATE_SECONDARY) || GLOB.input_router.click_is(pa, TYPE_TABLE_GET(GLOB.input_router, click_catcher_table), INPUT_ACTION_SWAP_HANDS))
		return FALSE
	return TRUE

/client/MouseDown(atom/object, atom/location, control, params)
	. = ..()
	var/mob/living/L = mob
	if(!istype(L))
		return
	if(!autofire_is_map_left_click(object, params))
		return
	var/obj/item/gun/G = L.get_active_hand()
	if(istype(G) && G.automatic)
		L.start_autofire(G, object, params)

/client/MouseUp(atom/object, atom/location, control, params)
	. = ..()
	var/mob/living/L = mob
	if(istype(L))
		L.stop_autofire()

/client/MouseDrag(src_object, atom/over_object, src_location, over_location, src_control, over_control, params)
	. = ..()
	var/mob/living/L = mob
	if(!istype(L) || !L.autofire_on)
		return
	// Sweep fire: keep shooting at whatever the cursor is now over, as long as
	// it is a point on the map rather than a HUD element.
	if(isatom(over_object) && !istype(over_object, /atom/movable/screen))
		L.update_autofire_target(over_object, params)

/// the autofire_gun this refers to (a relation view: null once it is deleted).
/mob/living/proc/autofire_gun() as /obj/item/gun
	return autofire_gun

/// the autofire_target this refers to (a relation view: null once it is deleted).
/mob/living/proc/autofire_target() as /atom
	return autofire_target
