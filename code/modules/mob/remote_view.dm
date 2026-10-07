/**
 * Use this if you need to remote view something. Remote view will end if you move or the remote view target is deleted. Cleared automatically if another remote view begins.
 *
 * An owned datum held by the viewing mob in /mob/var/remote_view (one at a time). Start one with
 * viewer.begin_remote_view(view_type, focused_on, viewsize, vconfig_path, ...subtype args).
 */
/datum/remote_view
	VAR_PROTECTED/datum/remote_view_config/settings = null
	VAR_PROTECTED/mob/host_mob
	VAR_PROTECTED/atom/remote_view_target

CAPABILITIES(/datum/remote_view)
	owns_one(nameof(settings), /datum/remote_view_config)

/mob
	/// The active remote view of this mob, if any (see begin_remote_view()).
	var/tmp/datum/remote_view/remote_view


/**
 * Starts a remote view of `view_type` on this mob, replacing any current one.
 * extra1..extra3 are the subtype's own start() arguments, in order:
 * * item_zoom: our_item, tileoffset, show_visible_messages
 * * viewer_managed: coordinator, viewer_list
 * Returns the new view, or null if it could not start.
 */
/mob/proc/begin_remote_view(view_type = /datum/remote_view, atom/focused_on, viewsize, vconfig_path, extra1, extra2, extra3)
	if(QDELETED(src))
		return null
	var/datum/remote_view/old_view = remote_view
	var/datum/remote_view/new_view = new view_type(src)
	if(!new_view.start(focused_on, viewsize, vconfig_path, extra1, extra2, extra3))
		new_view.forget_host() // never attached: nothing to restore
		spent(new_view)
		return null
	// Like the old component's highlander replace: the previous view goes after the new one began.
	if(old_view && old_view != new_view && !QDELETED(old_view))
		spent(old_view)
	rel_set(src, nameof(remote_view), new_view)
	new_view.attach()
	return new_view

/datum/remote_view/New(mob/viewer)
	..()
	rel_set(src, nameof(host_mob), viewer) // one-sided back view: the mob owns us in remote_view

/// Drops the host without restoring its perspective: for a view that never started.
/datum/remote_view/proc/forget_host()
	rel_clear(src, nameof(host_mob))

/// Begins the view (was the component's Initialize). Returns FALSE if the view cannot start.
/datum/remote_view/proc/start(atom/focused_on, viewsize, vconfig_path)
	if(!ismob(host_mob))
		return FALSE
	// Set config
	if(!vconfig_path)
		vconfig_path = /datum/remote_view_config
	rel_set(src, nameof(settings), new vconfig_path)
	// Safety check, focus on ourselves if the target is deleted, and flag any movement to end the view.
	if(QDELETED(focused_on))
		focused_on = host_mob
		settings.forbid_movement = TRUE
	// Begin remoteview
	host_mob.reset_perspective(focused_on) // Must be done before hooking the events
	if(settings.forbid_movement)
		observe(host_mob, /datum/notice/moved, src, then(PROC_REF(on_hostmob_moved_event)))
	else
		observe(host_mob, /datum/notice/movable_z_changed, src, then(PROC_REF(on_hostmob_moved_event)))
	observe(host_mob, /datum/notice/mob_reset_perspective, src, then(PROC_REF(on_reset_perspective)))
	observe(host_mob, /datum/notice/remote_view_clear, src, then(PROC_REF(on_forced_endview_event)))
	// Upon any disruptive status effects
	if(settings.will_stun)
		observe(host_mob, /datum/notice/living_status_stun, src, then(PROC_REF(on_status_effect_event)))
	if(settings.will_weaken)
		observe(host_mob, /datum/notice/living_status_weaken, src, then(PROC_REF(on_status_effect_event)))
	if(settings.will_paralyze)
		observe(host_mob, /datum/notice/living_status_paralyze, src, then(PROC_REF(on_status_effect_event)))
	if(settings.will_sleep)
		observe(host_mob, /datum/notice/living_status_sleep, src, then(PROC_REF(on_status_effect_event)))
	if(settings.will_blind)
		observe(host_mob, /datum/notice/living_status_blind, src, then(PROC_REF(on_status_effect_event)))
	if(settings.will_death)
		observe(host_mob, /datum/notice/mob_death, src, then(PROC_REF(handle_endview)))
	// Handle relayed movement
	if(settings.relay_movement)
		observe(host_mob, /datum/act/relay_movement, src, instead(then(PROC_REF(handle_relay_movement))))
	observe(host_mob, /datum/notice/mob_handle_vision, src, then(PROC_REF(handle_mob_vision_update)))
	// Hud overrides
	if(settings.override_entire_hud)
		observe(host_mob, /datum/act/draw_hud, src, instead(then(PROC_REF(handle_hud_override))))
	if(settings.override_health_hud)
		observe(host_mob, /datum/act/draw_health_icon, src, instead(then(PROC_REF(handle_hud_health))))
	if(settings.override_darkvision_hud)
		observe(host_mob, /datum/notice/mob_handle_hud_darksight, src, then(PROC_REF(handle_hud_darkvision)))
	// Recursive move fires this, we only want it to handle stuff like being inside a paicard when releasing turf lock
	if(isturf(focused_on))
		observe(host_mob, /datum/notice/movable_attempted_move, src, then(PROC_REF(on_recursive_moved_event)))
	// Focus on remote view
	rel_set(src, nameof(remote_view_target), focused_on)
	if(host_mob != remote_view_target) // Some items just offset our view, so we set ourselves as the view target, don't double dip if so!
		observe(remote_view_target, /datum/notice/qdeleting, src, then(PROC_REF(handle_endview)))
		observe(remote_view_target, /datum/notice/mob_reset_perspective, src, then(PROC_REF(on_remotetarget_reset_perspective)))
		observe(remote_view_target, /datum/notice/remote_view_clear, src, then(PROC_REF(on_forced_endview_event)))
	// If the user has already limited their HUD this avoids them having a HUD when they zoom in
	if(settings.use_zoom_hud && host_mob.hud_used.hud_shown)
		host_mob.toggle_zoom_hud()
	// Set view to size, null is default
	host_mob.set_viewsize(viewsize)
	return TRUE

/// Called once the view is the mob's remote_view (was RegisterWithParent).
/datum/remote_view/proc/attach()
	// The mob's sight and HUD re-read its view (the presentation reactions read MOB_KEY_VIEW).
	PUBLISH_CHANGE(host_mob, MOB_KEY_VIEW)
	settings.attached_to_mob(src, host_mob)

// Runs in destroy phase 1, before phase 4 nulls the declared refs: the viewer's eye,
// view size, hud and vision are restored (was the component's Destroy).
/datum/remote_view/lifecycle_unbind()
	. = ..()
	if(!host_mob)
		return
	unobserve_all(src)
	// Phase 2 then takes us out of host_mob.remote_view (the mob owns its view).
	// Reset to default size
	host_mob.set_viewsize()
	if(settings?.use_zoom_hud && !host_mob.hud_used.hud_shown)
		host_mob.toggle_zoom_hud()
	// Update the mob's vision right away if it still exists
	if(!QDELETED(host_mob))
		settings?.detatch_from_mob(src, host_mob)
		settings?.handle_remove_visuals(src, host_mob)
		PUBLISH_CHANGE(host_mob, MOB_KEY_VIEW)
	rel_clear(src, nameof(host_mob))
	rel_clear(src, nameof(remote_view_target))

// Event handlers

/datum/remote_view/proc/on_hostmob_moved_event(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	PRIVATE_PROC(TRUE)
	var/atom/source = N.target
	var/atom/oldloc
	if(istype(N, /datum/notice/moved))
		var/datum/notice/moved/moved_event = N
		oldloc = moved_event.old_loc
	handle_hostmob_moved(source, oldloc)

/datum/remote_view/proc/handle_hostmob_moved(atom/source, atom/oldloc)
	SHOULD_NOT_SLEEP(TRUE)
	PROTECTED_PROC(TRUE)
	RETURN_TYPE(null)
	if(!host_mob)
		return
	end_view()
	spent(src)

/datum/remote_view/proc/on_recursive_moved_event(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	PRIVATE_PROC(TRUE)
	var/atom/source = A.target
	var/datum/notice/movable_attempted_move/event = A
	handle_recursive_moved(source, event.old_loc, event.new_loc)

/datum/remote_view/proc/handle_recursive_moved(atom/source, atom/oldloc, atom/new_loc)
	SHOULD_NOT_SLEEP(TRUE)
	PROTECTED_PROC(TRUE)
	RETURN_TYPE(null)
	ASSERT(isturf(remote_view_target))
	// This handler is for recursive move decoupling us from /datum/remote_view/mob_holding_item's turf focusing when dropped in an item like a paicard
	// It is only hooked when we focus on a turf. Check the subtype for more info, this horrorshow took several days to make consistently behave.
	if(!host_mob)
		return
	end_view()
	spent(src)

/datum/remote_view/proc/on_forced_endview_event(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	PRIVATE_PROC(TRUE)
	var/datum/source = A.target
	handle_forced_endview(source)

/// By default pass this down, but we need unique handling for subtypes sometimes
/datum/remote_view/proc/handle_forced_endview(datum/source)
	SHOULD_NOT_SLEEP(TRUE)
	PROTECTED_PROC(TRUE)
	RETURN_TYPE(null)
	handle_endview()

/datum/remote_view/proc/handle_endview(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	RETURN_TYPE(null)
	if(!host_mob)
		return
	end_view()
	spent(src)

/datum/remote_view/proc/on_status_effect_event(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	PRIVATE_PROC(TRUE)
	var/datum/source = N.target
	var/amount = 0
	if(istype(N, /datum/notice/living_status_stun))
		var/datum/notice/living_status_stun/stun_event = N
		amount = stun_event.amount
	else if(istype(N, /datum/notice/living_status_weaken))
		var/datum/notice/living_status_weaken/weaken_event = N
		amount = weaken_event.amount
	else if(istype(N, /datum/notice/living_status_paralyze))
		var/datum/notice/living_status_paralyze/paralyze_event = N
		amount = paralyze_event.amount
	else if(istype(N, /datum/notice/living_status_sleep))
		var/datum/notice/living_status_sleep/sleep_event = N
		amount = sleep_event.amount
	else if(istype(N, /datum/notice/living_status_blind))
		var/datum/notice/living_status_blind/blind_event = N
		amount = blind_event.amount
	handle_status_effects(source, amount)

/datum/remote_view/proc/handle_status_effects(datum/source, amount)
	SHOULD_NOT_SLEEP(TRUE)
	PROTECTED_PROC(TRUE)
	RETURN_TYPE(null)
	if(!host_mob)
		return
	// We don't really care what effect was caused, just that it was increasing the value and thus negatively affecting us.
	if(amount <= 0)
		return
	if(host_mob.client && isturf(host_mob.client.eye) && host_mob.client.eye == get_turf(host_mob.client.mob)) // This handles turf decoupling being protected until we actually move.
		return
	handle_endview()

/datum/remote_view/proc/on_reset_perspective(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	PRIVATE_PROC(TRUE)
	RETURN_TYPE(null)
	if(!host_mob)
		return
	// Check if we're still remote viewing the SAME target!
	if(host_mob.client.eye == remote_view_target)
		return
	// The object already changed it's view, lets not interupt it like the others
	spent(src)

/datum/remote_view/proc/on_remotetarget_reset_perspective(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	PRIVATE_PROC(TRUE)
	RETURN_TYPE(null)
	// Non-mobs can't do this anyway
	if(!host_mob)
		return
	if(!ismob(remote_view_target))
		return
	var/mob/remote_view_mob = remote_view_target
	// This is an ugly one, but if we want to follow the other object properly we need to copy its state!
	if(!remote_view_mob.client || !host_mob.client)
		end_view()
		spent(src)
		return
	// Only continue to observe if their view location is the same as their turf. otherwise they are doing their own ACTUALLY-REMOTE viewing
	// we just won't update it if you're trying to look at the remote view target of another mob as they remote view someone else!
	if(get_turf(remote_view_mob) != get_turf(remote_view_mob.client.eye))
		host_mob.client.eye = remote_view_mob
		host_mob.client.perspective = MOB_PERSPECTIVE
		return
	// Copy the view, do not use reset_perspective, because it will fire our reset event and end our view!
	host_mob.client.eye = remote_view_mob.client.eye
	host_mob.client.perspective = remote_view_mob.client.perspective

/datum/remote_view/proc/end_view()
	PROTECTED_PROC(TRUE)
	RETURN_TYPE(null)
	host_mob.reset_perspective()

// Optional event handlers for more advanced remote views

/datum/remote_view/proc/handle_relay_movement(datum/act/relay_movement/move)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	if(!host_mob)
		return HOOK_DECLINE
	return settings.handle_relay_movement(src, host_mob, move.direction) ? TRUE : HOOK_DECLINE

/datum/remote_view/proc/handle_hud_override(datum/act/draw_hud/draw)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	if(!host_mob)
		return HOOK_DECLINE
	return settings.handle_hud_override(src, host_mob) ? TRUE : HOOK_DECLINE

/datum/remote_view/proc/handle_hud_health(datum/act/draw_health_icon/draw)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	if(!host_mob)
		return HOOK_DECLINE
	return settings.handle_hud_health(src, host_mob) ? TRUE : HOOK_DECLINE

/datum/remote_view/proc/handle_hud_darkvision(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	RETURN_TYPE(null)
	PRIVATE_PROC(TRUE)
	if(!host_mob)
		return
	settings.handle_hud_darkvision(src, host_mob)

/datum/remote_view/proc/handle_mob_vision_update(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	if(!host_mob)
		return
	return settings.handle_apply_visuals(src, host_mob)

// Accessors

/datum/remote_view/proc/get_host()
	RETURN_TYPE(/mob)
	return host_mob

/datum/remote_view/proc/get_target()
	RETURN_TYPE(/atom)
	return remote_view_target

/datum/remote_view/proc/get_coordinator()
	RETURN_TYPE(/atom)
	return null // For subtype

/datum/remote_view/proc/looking_at_target_already(atom/target)
	return (remote_view_target == target)

/**
 * Remote view subtype where if the item used with it is moved or dropped the view ends too
 */
/datum/remote_view/item_zoom
	VAR_PRIVATE/obj/item/host_item
	VAR_PRIVATE/show_message


/datum/remote_view/item_zoom/start(atom/focused_on, viewsize, vconfig_path, obj/item/our_item, tileoffset, show_visible_messages)
	. = ..()
	if(!.)
		return
	rel_set(src, nameof(host_item), our_item)
	observe(host_item, /datum/notice/qdeleting, src, then(PROC_REF(handle_endview)))
	observe(host_item, /datum/notice/moved, src, then(PROC_REF(handle_endview)))
	observe(host_item, /datum/notice/item_dropped, src, then(PROC_REF(handle_endview)))
	observe(host_item, /datum/notice/item_equipped, src, then(PROC_REF(handle_endview)))
	observe(host_item, /datum/notice/remote_view_clear, src, then(PROC_REF(on_forced_endview_event)))
	// Unfortunately too many things read this to control item state for me to remove this.
	// Oh well! better than looking the view up everywhere. Lets just manage item/zoom in this datum though...
	our_item.zoom = TRUE
	// Offset view
	var/tilesize = 32
	var/viewoffset = tilesize * tileoffset
	switch(host_mob.dir)
		if (NORTH)
			host_mob.client.pixel_x = 0
			host_mob.client.pixel_y = viewoffset
		if (SOUTH)
			host_mob.client.pixel_x = 0
			host_mob.client.pixel_y = -viewoffset
		if (EAST)
			host_mob.client.pixel_x = viewoffset
			host_mob.client.pixel_y = 0
		if (WEST)
			host_mob.client.pixel_x = -viewoffset
			host_mob.client.pixel_y = 0
	// Feedback
	show_message = show_visible_messages
	if(show_message)
		host_mob.visible_message(span_filter_notice("[host_mob] peers through the [host_item.zoomdevicename ? "[host_item.zoomdevicename] of the [host_item.name]" : "[host_item.name]"]."))
	PUBLISH_CHANGE(host_mob, MOB_KEY_VIEW)

// The zooming item un-zooms and the viewer's client offset resets.
/datum/remote_view/item_zoom/lifecycle_unbind()
	if(host_mob && host_item)
		// Feedback
		if(show_message)
			host_mob.visible_message(span_filter_notice("[host_item.zoomdevicename ? "[host_mob] looks up from the [host_item.name]" : "[host_mob] lowers the [host_item.name]"]."))
		host_item.zoom = FALSE
		if(host_mob.client)
			host_mob.client.pixel_x = 0
			host_mob.client.pixel_y = 0
		PUBLISH_CHANGE(host_mob, MOB_KEY_VIEW)
	rel_clear(src, nameof(host_item))
	. = ..()

/**
 * Remote view subtype that stops if the remote view target is dead, or you lose access to the mremote mutation
 */
/datum/remote_view/mremote_mutation

/datum/remote_view/mremote_mutation/start(atom/focused_on, viewsize, vconfig_path)
	if(!ismob(focused_on)) // What are you doing? This gene only works on mob targets, if you adminbus this I will personally eat your face.
		return FALSE
	. = ..()
	if(!.)
		return
	// Remote view mutation stops viewing when mobs die or if we lose the mutation/gene
	observe(host_mob, /datum/notice/mob_dna_mutation, src, then(PROC_REF(on_mutation)))
	if(host_mob != remote_view_target)
		observe(remote_view_target, /datum/notice/mob_death, src, then(PROC_REF(handle_endview)))

/datum/remote_view/mremote_mutation/proc/on_mutation(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	PRIVATE_PROC(TRUE)
	if(!host_mob)
		return
	var/mob/remote_mob = remote_view_target
	if(host_mob.stat == CONSCIOUS && (host_mob.has_mutation(mRemote)) && remote_mob && remote_mob.stat == CONSCIOUS)
		return
	end_view()
	spent(src)

/**
 * Remote view subtype that handles look() and unlook() procs while managing the coordinator's
 * `viewers` relation list view (the viewing mobs; a deleted viewer leaves it).
 */
/datum/remote_view/viewer_managed
	VAR_PRIVATE/datum/view_coordinator // The object whose `viewers` list we join, with look() and unlook() logic (a relation view)


/datum/remote_view/viewer_managed/start(atom/focused_on, viewsize, vconfig_path, datum/coordinator, list/viewer_list)
	. = ..()
	if(!.)
		return
	rel_set(src, nameof(view_coordinator), coordinator)
	view_coordinator.look(host_mob)
	if("viewers" in view_coordinator.vars)
		rel_add(view_coordinator, nameof(/datum/action::viewers), host_mob)
	observe(view_coordinator, /datum/notice/remote_view_clear, src, then(PROC_REF(on_forced_endview_event)))

// The view coordinator stops showing to this viewer.
/datum/remote_view/viewer_managed/lifecycle_unbind()
	if(host_mob && view_coordinator)
		view_coordinator.unlook(host_mob, FALSE)
		if("viewers" in view_coordinator.vars)
			rel_remove(view_coordinator, nameof(/datum/action::viewers), host_mob)
	rel_clear(src, nameof(view_coordinator))
	. = ..()

/datum/remote_view/viewer_managed/get_coordinator()
	return view_coordinator

/**
 * Remote view subtype that is handling a byond bug where mobs changing their client eye from inside of
 * and object will not have their eye change, and instead focus on any mob currently holding the item,
 * and only be released once we move ourselves to a new turf. This subtype does some loc witchcraft
 * to put us on a turf, change our view, and put us back without calling move/enter.
 * Hopefully this will not be needed someday in the future - Willbird
 */
#define MAX_RECURSIVE 64
/datum/remote_view/mob_holding_item
	var/needs_to_decouple = FALSE // if the current top level atom is a mob

/datum/remote_view/mob_holding_item/start(atom/focused_on, viewsize, vconfig_path)
	if(!isobj(focused_on)) // You shouldn't be using this if so.
		return FALSE
	. = ..()
	if(!.)
		return
	// Items can be nested deeply, so we need to update on any parent reorganization or actual move.
	dq_add_recursive_move(host_mob)
	observe(host_mob, /datum/notice/movable_attempted_move, src, then(PROC_REF(on_recursive_moved_event))) // Doesn't need override, basetype only ever hooks this if we're looking at a turf
	// Check our inmob state
	if(ismob(find_topmost_atom()))
		needs_to_decouple = TRUE

/datum/remote_view/mob_holding_item/handle_status_effects(datum/source, amount)
	if(host_mob.loc == remote_view_target) // If we are still inside our holder or belly than don't bother spamming this
		return
	. = ..()

/datum/remote_view/mob_holding_item/handle_hostmob_moved(atom/source, atom/oldloc)
	// We handle this in recursive move
	if(!host_mob)
		return
	if(isturf(host_mob.loc))
		if(oldloc == remote_view_target)
			needs_to_decouple = TRUE
		decouple_view_to_turf( host_mob, host_mob.loc)
		return

/datum/remote_view/mob_holding_item/handle_recursive_moved(atom/source, atom/oldloc, atom/new_loc)
	if(!host_mob)
		return
	// default moved handler will handle this
	if(isturf(host_mob.loc))
		return
	// This only triggers when we are deeper in than our mob. See who is in charge of this clowncar...
	// Loop upward until we find a mob or a turf. Mobs will hold our current view, turfs mean our bag-stack was dropped.
	var/atom/top_most = find_topmost_atom()
	if(isturf(top_most))
		if(needs_to_decouple) // Only need to do this if we were held by a mob prior, otherwise this triggers every move and is expensive for no reason
			decouple_view_to_turf( host_mob, top_most)
		return
	if(ismob(top_most) || ismecha(top_most)) // Mobs and mechas both do this
		dq_add_recursive_move(host_mob) // Will rebuild parent chain.
		needs_to_decouple = TRUE
		return

/// Get our topmost atom state, if it's a mob or a turf
/datum/remote_view/mob_holding_item/proc/find_topmost_atom()
	var/atom/cur_parent = remote_view_target?.loc // first loc could be null
	var/recursion = 0 // safety check - max iterations
	while(!isnull(cur_parent) && (recursion < MAX_RECURSIVE))
		if(cur_parent == cur_parent.loc) //safety check incase a thing is somehow inside itself, cancel
			log_runtime("REMOTE_VIEW: Parent is inside itself. ([host_mob]) ([host_mob.type]) : [MAX_RECURSIVE - recursion]")
			return null
		if(ismob(cur_parent) || ismecha(cur_parent) || isturf(cur_parent))
			return cur_parent
		recursion++
		cur_parent = cur_parent.loc

	if(recursion >= MAX_RECURSIVE) // If we escaped due to iteration limit, cancel
		log_runtime("REMOTE_VIEW: Turf search hit recursion limit. ([host_mob]) ([host_mob.type])")
	return null

/// Makes a new remote view focused on the release_turf argument. This remote view ends as soon as any movement happens. Even if we are inside many levels of objects due to our recursive_move listener
/datum/remote_view/mob_holding_item/proc/decouple_view_to_turf(mob/cache_mob, turf/release_turf)
	if(needs_to_decouple)
		// Yes this spawn is needed, yes I wish it wasn't.
		after(cache_mob, 0, GLOBAL_PROC_REF(remote_view_decouple), with = list(cache_mob, release_turf), keeps_dead = TRUE) // Yes this deferral is needed: the view deletes itself below
		// Because nested vore bellies do NOT get handled correctly for recursive prey. We need to tell the belly's occupants to decouple too... Then their own belly's occupants...
		// Yes, two loops is faster. Because we skip typechecking byondcode side and instead do it engine side when getting the contents of the mob,
		// we also skip typechecking every /obj in the mob on the byondcode side... Evil wizard knowledge.
		for(var/obj/belly/check_belly in contents_of(cache_mob))
			PUBLISH_LEGACY(check_belly, /datum/notice/remote_view_clear)
		for(var/obj/item/dogborg/sleeper/check_sleeper in contents_of(cache_mob))
			PUBLISH_LEGACY(check_sleeper, /datum/notice/remote_view_clear)
	spent(src)

/// We were forcibly disconnected, this situation is probably a recursive hellscape, so just decouple entirely and fix it when someone moves.
/datum/remote_view/mob_holding_item/handle_forced_endview(atom/source)
	if(!host_mob)
		return
	needs_to_decouple = TRUE
	decouple_view_to_turf( host_mob, get_turf(host_mob))

#undef MAX_RECURSIVE

/// Decouple the view to the turf on drop, or we'll be stuck on the mob that dropped us forever.
/proc/remote_view_decouple(mob/cache_mob, turf/release_turf)
	if(!cache_mob.client)
		cache_mob.reset_perspective()
		return
	cache_mob.begin_remote_view(/datum/remote_view, release_turf, null, /datum/remote_view_config/turf_decoupling)
	cache_mob.client.eye = release_turf // Yes--
	cache_mob.client.perspective = EYE_PERSPECTIVE // --this is required too.
	if(!isturf(cache_mob.loc)) // For stuff like paicards
		dq_add_recursive_move(cache_mob) // Will rebuild parent chain.
