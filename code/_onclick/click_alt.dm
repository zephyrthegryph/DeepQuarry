///Main proc for primary alt click
/mob/proc/AltClickOn(atom/target)
	base_click_alt(target)

/**
 * ### Base proc for alt click interaction left click. Returns if the click was intercepted & handled
 *
 * If you wish to add custom `click_alt` behavior for a single type, use that proc.
 */
/mob/proc/base_click_alt(atom/target)
	SHOULD_NOT_OVERRIDE(TRUE)

	// Check if they've hooked in to prevent src from alt clicking anything

	// If it has a signal handler that returns a click action, done.
	if(SEND_SIGNAL(target, COMSIG_CLICK_ALT, src) & CLICK_ACTION_ANY)
		return TRUE

	// If it has a custom click_alt that returns success/block, done.
	return target.click_alt(src) & CLICK_ACTION_ANY
	/* //NYI Start
	if(can_perform_action(target, (target.interaction_flags_click | SILENT_ADJACENCY)))
		return target.click_alt(src) & CLICK_ACTION_ANY

	return FALSE
	*/  //NYI Start

/mob/living/base_click_alt(atom/target)
	SHOULD_NOT_OVERRIDE(TRUE)

	. = ..()
	if(.)
		return

	return try_open_loot_panel_on(target)

/**
 * ## Custom alt click interaction
 * Override this to change default alt click behavior. Return `CLICK_ACTION_SUCCESS`, `CLICK_ACTION_BLOCKING` or `NONE`.
 *
 * ### Guard clauses
 * Consider adding `interaction_flags_click` before adding unique guard clauses.
 *
 * ### Return flags
 * Forgetting your return will cause the default alt click behavior to occur thereafter.
 *
 * The difference between NONE and BLOCKING can get hazy, but I like to keep NONE limited to guard clauses and "never" cases.
 *
 * A good usage for BLOCKING over NONE is when it's situational for the item and there's some feedback indicating this.
 *
 * ### Examples:
 * User is a ghost, alt clicks on item with special disk eject: NONE
 *
 * Machine broken, no feedback: NONE
 *
 * Alt click a pipe to max output but its already max: BLOCKING
 *
 * Alt click a gun that normally works, but is out of ammo: BLOCKING
 *
 * User unauthorized, machine beeps: BLOCKING
 *
 * @param {mob} user - The person doing the alt clicking.
 */

/atom/proc/click_alt(mob/user)
	SHOULD_CALL_PARENT(FALSE)
	// Converted handlers (I7): interactions with entry = INTERACTION_ENTRY_ALT, where the override ran.
	var/list/outcome = list()
	var/datum/interaction/answered = run_interaction_entry(user, src, user.get_active_hand(), INTERACTION_ENTRY_ALT, outcome)
	if(answered)
		if(!answered.consumes_input)
			return NONE
		return (INTERACTION_TRY_RAN in outcome) ? CLICK_ACTION_SUCCESS : CLICK_ACTION_BLOCKING
	// if(!user.can_interact_with(src))
	// 	return FALSE

	if(SEND_SIGNAL(src, COMSIG_CLICK_ALT, user) & COMSIG_MOB_CANCEL_CLICKON)
		return TRUE

	if(HAS_TRAIT(src, TRAIT_ALT_CLICK_BLOCKER) && !isobserver(user))
		return TRUE

	var/turf/tile = get_turf(src)
	if(isnull(tile))
		return FALSE

	if(!isturf(loc) && !isturf(src))
		return FALSE

	if(!user.TurfAdjacent(tile))
		return FALSE

	var/datum/lootpanel/panel = user.client?.loot_panel
	if(isnull(panel))
		return FALSE

	panel.open(tile)
	return TRUE

///Main proc for secondary alt click
/mob/proc/AltClickSecondaryOn(atom/target)
	base_click_alt_secondary(target)

/**
 * ### Base proc for alt click interaction right click.
 *
 * If you wish to add custom `click_alt_secondary` behavior for a single type, use that proc.
 */
/mob/proc/base_click_alt_secondary(atom/target)
	SHOULD_NOT_OVERRIDE(TRUE)

	//Hook on the mob to intercept the click

	//Hook on the atom to intercept the click

	// If it has a custom click_alt_secondary then do that
	target.click_alt_secondary(src)
	/* //NYI
	if(can_perform_action(target, target.interaction_flags_click | SILENT_ADJACENCY))
		target.click_alt_secondary(src)
	*/

/**
 * ## Custom alt click secondary interaction
 * Override this to change default alt right click behavior.
 *
 * ### Guard clauses
 * Consider adding `interaction_flags_click` before adding unique guard clauses.
 **/
/atom/proc/click_alt_secondary(mob/user)
	SHOULD_CALL_PARENT(FALSE)
	return NONE

/**
 * ## No-op for unambiguous loot panel bind as a non-living mob.
 **/
/mob/proc/alt_shift_click_on(atom/target)
	SHOULD_NOT_OVERRIDE(TRUE)
	return FALSE

/**
 * ## Bind for unambiguously opening the loot panel as a living mob.
 * This raises no signals and is not meant to have its behavior overridden.
 **/
/mob/living/alt_shift_click_on(atom/target)
	SHOULD_NOT_OVERRIDE(TRUE)
	return try_open_loot_panel_on(target)

///Helper for determining if a living mob may open the loot panel for some target, since it is shared between
///alt and alt-shift click.
///Returns FALSE if the mob is unable to open the loot panel at the target and TRUE if the loot panel was opened.
/mob/living/proc/try_open_loot_panel_on(atom/target)
	//Just a copy past of /mob/living/MouseDrop until we get the loot panel.
	var/mob/living/living_target = target
	if(living_target.is_incorporeal())
		return
	if(istype(living_target) && living_target != src && Adjacent(living_target))
		living_target.show_inventory_panel(src) //We don't have the loot panel, so...We'll use our inventory panel for now.

