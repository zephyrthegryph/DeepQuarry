
/*
	This is a special scanner which exists to give explorers something to do besides shoot things.
	The scanner is able to be used on certain things in the world, and after a variable delay, the scan finishes,
	giving the person who scanned it some fluff and information about what they just scanned,
	as well as points that currently do nothing but measure epeen,
	and will be used as currency in The Future(tm) to buy things explorers care about.

	Scanning hostile mobs and objects is tricky since only mobs that are alive are scannable, so scanning
	them requires careful position to stay out of harms way until the scan finishes. That is why
	the person with the scanner gets a visual box that shows where they are allowed to move to
	without inturrupting the scan.
*/
/obj/item/cataloguer/get_mechanics_info(list/additional_information)
	return ..(list("Scanning requires staying within a certain radius of the target until the scan finishes. \
	An interrupted scan resumes where it left off if the same thing is scanned again.") + additional_information)

/obj/item/cataloguer
	name = "cataloguer"
	desc = "A hand-held device, used for compiling information about an object by scanning it. Alt+click to highlight scannable objects around you."
	icon = 'icons/obj/device.dmi'
	icon_state = "cataloguer"
	w_class = ITEMSIZE_NORMAL
	force = 0
	slot_flags = SLOT_BELT
	var/points_stored = 0 // Amount of 'exploration points' this device holds.
	var/scan_range = 3 // How many tiles away it can scan. Changing this also changes the box size.
	var/credit_sharing_range = 280 // If another person is within this radius, they will also be credited with a successful scan. Original was 14
	var/datum/category_item/catalogue/displayed_data = null // Used for viewing a piece of data in the UI.
	var/debug = FALSE // If true, can view all catalogue data defined, regardless of unlock status.
	var/atom/partial_scanned = null // The thing that was last scanned if inturrupted (a relation view). Used to allow for partial scans to be resumed.
	var/partial_scan_time = 0 // How much to make the next scan shorter.

/obj/item/cataloguer/advanced
	name = "advanced cataloguer"
	icon = 'icons/obj/device.dmi'
	icon_state = "adv_cataloguer"
	desc = "A hand-held device, used for compiling information about an object by scanning it. This one is an upgraded model, \
	with a scanner that both can scan from farther away, and with less time."
	scan_range = 4
	toolspeed = 0.8

// Able to see all defined catalogue data regardless of if it was unlocked, intended for testing.
/obj/item/cataloguer/debug
	name = "omniscient cataloguer"
	desc = "A hand-held cataloguer device that appears to be plated with gold. For some reason, it \
	just seems to already know everything about narrowly defined pieces of knowledge one would find \
	from nearby, perhaps due to being colored gold. Truly a epistemological mystery."
	icon = 'icons/obj/device.dmi'
	icon_state = "debug_cataloguer"
	toolspeed = 0.1
	scan_range = 7
	debug = TRUE

REGISTRY_MEMBERSHIP(/obj/item/cataloguer, REGISTRY_CATALOGUERS)

/// Appearance reader: TRUE while a scan task holds the cataloguer.
/obj/item/cataloguer/proc/appearance_busy()
	return work_busy(src) ? TRUE : FALSE

/// The look (the draw sweep: from its template).
/obj/item/cataloguer/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][appearance_busy() ? "_active" : ""]")

/obj/item/cataloguer/afterattack(atom/target, mob/user, proximity_flag)
	// Things that invalidate the scan immediately.
	if(work_busy(src))
		to_chat(user, span_warning("\The [src] is already scanning something."))
		return

	if(isturf(target) && (!target.can_catalogue()))
		var/turf/T = target
		for(var/atom/A as anything in contents_of(T)) // If we can't scan the turf, see if we can scan anything on it, to help with aiming.
			if(A.can_catalogue())
				target = A
				break

	if(!target.can_catalogue(user)) // This will tell the user what is wrong.
		return

	if(get_dist(target, user) > scan_range)
		to_chat(user, span_warning("You are too far away from \the [target] to catalogue it. Get closer."))
		return

	// Get how long the delay will be.
	var/scan_delay = target.get_catalogue_delay() * toolspeed
	if(partial_scanned)
		if(partial_scanned == target)
			scan_delay -= partial_scan_time
			to_chat(user, span_notice("Resuming previous scan."))
		else
			to_chat(user, span_warning("Scanning new target. Previous scan buffer cleared."))

	// Start the special effects.
	var/datum/beam/scan_beam = user.Beam(target, icon_state = "rped_upgrade", time = scan_delay)
	var/filter = filter(type = "outline", size = 1, color = "#FFFFFF")
	target.filters += filter
	var/list/box_segments = list()
	if(user.client)
		box_segments = draw_box(target, scan_range, user.client)
		color_box(box_segments, "#00FFFF", scan_delay)

	play_sfx(src, SFX_MACHINES_BEEP)

	// The delay, and test for if the scan succeeds or not. The effects travel in a list so the
	// beam (which ends itself) is never a captured argument.
	var/list/effects = list(scan_beam, filter, box_segments)
	// The scan claims the cataloguer: busy (task_busy()) until it ends.
	var/started = task_start(/datum/task/timed/cataloguer_scan, user, target, duration = scan_delay, effects = effects, scan_start_time = world.time, max_distance = scan_range, busy = src)
	if(istext(started))
		scan_cleanup(target, user, effects)
		return

/datum/task/timed/cataloguer_scan
	flags = IGNORE_USER_LOC_CHANGE|IGNORE_TARGET_LOC_CHANGE
	complete_proc = /obj/item/cataloguer/proc/scan_succeeded
	cancel_proc = /obj/item/cataloguer/proc/scan_failed
	var/list/effects
	var/scan_start_time

/obj/item/cataloguer/proc/scan_succeeded(datum/task/timed/cataloguer_scan/task)
	var/atom/target = task.target
	var/mob/user = task.actor
	var/list/effects = task.effects
	if(target.can_catalogue(user))
		to_chat(user, span_notice("You successfully scan \the [target] with \the [src]."))
		play_sfx(src, SFX_MACHINES_PING)
		catalogue_object(target, user)
	else
		// In case someone else scans it first, or it died, etc.
		to_chat(user, span_warning("\The [target] is no longer valid to scan with \the [src]."))
		play_sfx(src, SFX_MACHINES_BUZZ_TWO)

	rel_clear(src, nameof(partial_scanned))
	partial_scan_time = 0
	scan_cleanup(target, user, effects)

/obj/item/cataloguer/proc/scan_failed(datum/task/timed/cataloguer_scan/task)
	var/atom/target = task.target
	var/mob/user = task.actor
	var/list/effects = task.effects
	var/scan_start_time = task.scan_start_time
	to_chat(user, span_warning("You failed to finish scanning \the [target] with \the [src]."))
	play_sfx(src, SFX_MACHINES_BUZZ_TWO)
	color_box(effects[3], "#FF0000", 3)
	if(target)
		rel_set(src, nameof(partial_scanned), target)
	partial_scan_time += world.time - scan_start_time // This is added to the existing value so two partial scans will add up correctly.
	hold_busy(src, 0.3 SECONDS, TYPE_PROC_REF(/atom, update_icon)) // still busy while the box flashes red
	after(src, 0.3 SECONDS, PROC_REF(scan_cleanup_late), with = list(effects, target ? REF(target) : null, user ? REF(user) : null))

/obj/item/cataloguer/proc/scan_cleanup_late(list/effects, target_ref, user_ref)
	scan_cleanup(locate(target_ref), locate(user_ref), effects)

/obj/item/cataloguer/proc/scan_cleanup(atom/target, mob/user, list/effects)
	// Now clean up the effects.
	var/datum/beam/scan_beam = effects[1]
	if(!QDELETED(scan_beam))
		spent(scan_beam, user)
	if(target)
		target.filters -= effects[2]
	if(user?.client) // If for some reason they logged out mid-scan the box will be gone anyways.
		delete_box(effects[3], user.client)

// Todo: Display scanned information, increment points, etc.
/obj/item/cataloguer/proc/catalogue_object(atom/target, mob/living/user)
	// Figure out who may have helped out.
	var/list/contributers = list()
	var/list/contributer_names = list()
	for(var/mob/living/L as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(L == user)
			continue
		if(!istype(L))
			continue
		if(get_dist(L, user) <= credit_sharing_range)
			contributers += L
			contributer_names += L.name

	var/points_gained = 0

	// Discover each datum available.
	var/list/object_data = target.get_catalogue_data()
	if(LAZYLEN(object_data))
		for(var/data_type in object_data)
			var/datum/category_item/catalogue/I = GLOB.catalogue_data.resolve_item(data_type)
			if(istype(I))
				var/list/discoveries = I.discover(user, list(user.name) + contributer_names) // If one discovery leads to another, the list returned will have all of them.
				if(LAZYLEN(discoveries))
					for(var/datum/category_item/catalogue/data as anything in discoveries)
						points_gained += data.value

	// Give out points.
	if(points_gained)
		// First, to us.
		to_chat(user, span_notice("Gained [points_gained] points from this scan."))
		adjust_points(points_gained)

		// Now to our friends, if any.
		if(contributers.len)
			for(var/mob/M in contributers)
				var/list/things = M.GetAllContents(3) // Depth of two should reach into bags but just in case lets make it three.
				var/obj/item/cataloguer/other_cataloguer = locate_in_list(things, /obj/item/cataloguer) // If someone has two or more scanners this only adds points to one.
				if(other_cataloguer)
					to_chat(M, span_notice("Gained [points_gained] points from \the [user]'s scan of \the [target]."))
					other_cataloguer.adjust_points(points_gained)
			to_chat(user, span_notice("Shared discovery with [contributers.len] other contributer\s."))

/// Old click_alt.
/obj/item/cataloguer/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	pulse_scan(user)
	return TRUE

// Gives everything capable of being scanned an outline for a brief moment.
// Helps to avoid having to click a hundred things in a room for things that have an entry.
/obj/item/cataloguer/proc/pulse_scan(mob/user)
	if(work_busy(src))
		to_chat(user, span_warning("\The [src] is busy doing something else."))
		return

	// Busy (a hold claims it) while the highlights are up.
	if(istext(hold_busy(src, 2 SECONDS, TYPE_PROC_REF(/atom, update_icon))))
		return
	play_sfx(src, SFX_MACHINES_BEEP)

	// First, get everything able to be scanned.
	var/list/scannable_atoms = list()
	for(var/atom/A as anything in view(world.view, user))
		if(A.can_catalogue()) // Not passing the user is intentional, so they don't get spammed.
			scannable_atoms += A

	// Highlight things able to be scanned.
	var/filter = filter(type = "outline", size = 1, color = "#00FF00")
	for(var/atom/A as anything in scannable_atoms)
		A.filters += filter
	to_chat(user, span_notice("\The [src] is highlighting scannable objects in green, if any exist."))
	after(src, 2 SECONDS, PROC_REF(pulse_scan_end), with = list(user, list(scannable_atoms, filter)))

/obj/item/cataloguer/proc/pulse_scan_end(mob/user, list/state)
	var/list/scannable_atoms = state[1]
	var/filter = state[2]
	// Remove the highlights.
	for(var/atom/A as anything in scannable_atoms)
		if(QDELETED(A))
			continue
		A.filters -= filter

	if(scannable_atoms.len)
		play_sfx(src, SFX_MACHINES_PING)
	else
		play_sfx(src, SFX_MACHINES_BUZZ_TWO)
	to_chat(user, span_notice("\The [src] found [scannable_atoms.len] object\s that can be scanned."))

// Negative points are bad.
/obj/item/cataloguer/proc/adjust_points(amount)
	points_stored = max(0, points_stored += amount)

/obj/item/cataloguer/proc/cataloguer_controls_opened(datum/act/op/A)
	var/mob/living/user = A.actor
	interact(user)
	return OP_OK

/obj/item/cataloguer/interact(mob/user)
	// structured TGUI Cataloguer panel (see
	// code/modules/admin/cataloguer_panel.dm).
	tgui_interact(user)
	add_fingerprint(user)


/// Old attackby.
/obj/item/cataloguer/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/card/id) && !work_busy(src))
		var/obj/item/card/id/ID = W
		if(points_stored)
			var/datum/money_account/account = get_account(ID.associated_account_number)
			if(account?.credit(points_stored, name, "Catalogue data proceeds", name))
				points_stored = 0
			to_chat(user, span_notice("You swipe the id over \the [src]."))
		else
			to_chat(user, span_notice("\The [src] has no points available."))
	return OP_DECLINE

/obj/item/cataloguer/compact
	name = "compact cataloguer"
	desc = "A compact hand-held device, used for compiling information about an object by scanning it. \
	Alt+click to highlight scannable objects around you."
	icon = 'icons/obj/device.dmi'
	icon_state = "compact"
	actions_types = list(/datum/action/item_action/toggle_cataloguer)
	var/deployed = TRUE
	scan_range = 1
	toolspeed = 1.2

/obj/item/cataloguer/compact/pathfinder
	name = "pathfinder's cataloguer"
	desc = "A compact hand-held device, used for compiling information about an object by scanning it. \
	Alt+click to highlight scannable objects around you."
	icon = 'icons/obj/device.dmi'
	icon_state = "pathcat"
	scan_range = 3
	toolspeed = 1

/// The look (the draw sweep: from its template).
/obj/item/cataloguer/compact/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][appearance_busy() ? "_s" : ""]")

/obj/item/cataloguer/compact/ui_action_click(mob/user, actiontype)
	var/why = can_toggle_compact(user, src, null)
	if(why != TRUE)
		to_chat(user, span_warning("[why]."))
		return
	compact_toggle_effect(user)

/// Requirement: TRUE, or why the cataloguer can't be folded or deployed.
/obj/item/cataloguer/compact/proc/can_toggle_compact(mob/user, atom/target, obj/item/held)
	if(work_busy(src))
		return "\The [src] is currently scanning something"
	return TRUE

/obj/item/cataloguer/compact/proc/compact_toggle_effect(mob/user, obj/item/held, datum/interaction/interaction)
	deployed = !(deployed)
	if(deployed)
		w_class = ITEMSIZE_NORMAL
		icon_state = "[initial(icon_state)]"
		to_chat(user, span_notice("You flick open \the [src]."))
	else
		w_class = ITEMSIZE_SMALL
		icon_state = "[initial(icon_state)]_closed"
		to_chat(user, span_notice("You close \the [src]."))

	if (ismob(user))
		var/mob/M = user
		M.update_mob_action_buttons()

/obj/item/cataloguer/compact/afterattack(atom/target, mob/user, proximity_flag)
	if(!deployed)
		to_chat(user, span_warning("\The [src] is closed."))
		return
	return ..()

/obj/item/cataloguer/compact/pulse_scan(mob/user)
	if(!deployed)
		to_chat(user, span_warning("\The [src] is closed."))
		return
	return ..()

/// Old object verbs.
CAPABILITIES(/obj/item/cataloguer/compact)
	op("compact_toggle_effect", menu(), label("Toggle Cataloguer"), needs(carried(), req(PROC_REF(can_toggle_compact_holds), because = PROC_REF(can_toggle_compact_refusal))), then(PROC_REF(compact_toggle_effect_op)))

/// Requirement (was REQ_* can_toggle_compact): the legacy check answers TRUE to pass.
/obj/item/cataloguer/compact/proc/can_toggle_compact_holds(datum/act/op/A)
	var/answer = can_toggle_compact(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_toggle_compact_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/cataloguer/compact/proc/can_toggle_compact_refusal(datum/act/op/A)
	var/answer = can_toggle_compact(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/// The compact_toggle_effect op: the verb's effect, as the old resolver ran it.
/obj/item/cataloguer/compact/proc/compact_toggle_effect_op(datum/act/op/A)
	compact_toggle_effect(A.actor, A.held, null)
	return OP_OK

// The shown entry is a round-long catalogue definition.
