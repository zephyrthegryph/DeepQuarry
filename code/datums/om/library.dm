// Object-model core: the standard library of table rows
// (doc/rewrite/object_model_core.md, "Library"). Mob Life uses the clocks and suspension;
// statuses are stats (code/library/mob/statuses.dm).

/proc/om_library_effects()
	// ALLOW(sys_const_list_alloc): read once, while the OM registry builds inside the global controller's New(), before any GLOBAL_LIST_INIT exists
	return list(
		EFFECT_BUCKLED = list("combine" = COMBINE_ANY, "channel" = CHANGE_MOB_STATUS, "publishes" = MOB_KEY_STATUS),
		// Body effects (body_effects.dm): factor tables keyed by definition type, value = stacks.
		EFFECT_BODY_EFFECTS = list("combine" = COMBINE_SUM_PER_KEY, "channel" = CHANGE_MOB_CONDITIONS, "publishes" = MOB_KEY_CONDITIONS, "type" = /datum/om/effect/body_effects),
		// Grant kinds.
		GRANT_ABILITY = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_LANGUAGE = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_VERB = list("combine" = COMBINE_SUM_PER_KEY, "type" = /datum/om/effect/grant_verb),
		GRANT_VERB_HIDE = list("combine" = COMBINE_SUM_PER_KEY, "type" = /datum/om/effect/grant_verb),
		GRANT_CAPABILITY = list("combine" = COMBINE_SUM_PER_KEY, "type" = /datum/om/effect/grant_capability),
		GRANT_ACCESS = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_TRAIT = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_CADENCE = list("combine" = COMBINE_SUM_PER_KEY, "type" = /datum/om/effect/grant_cadence),
	)

// ---------------------------------------------------------------- relations

// A machine's occupant is a slot (/datum/om/relation/slot/occupant,
// containment.md §10), not a relation declared here: read it with SLOT_ITEM().

/// mob -> what it is buckled to. `buckled`/`buckled_mobs` are gone (OM
/// relations step 6): there is no stored field on either side any more --
/// BUCKLED()/BUCKLED_MOBS() (om.dm) read the edge directly, so this relation
/// no longer has any view state to keep in sync, only the real side effects
/// below (direction/canmove/floating/water, riding offsets, the buckled
/// alert, the buckle signal).
/// holds_while drops the edge outright (not just its EFFECT_BUCKLED contribution)
/// the moment the mob ends up off the buckled object's tile, e.g. a forced
/// move that didn't go through handle_buckled_mob_movement().
/datum/om/relation/buckled_to
	name = "buckle"
	source_single = TRUE
	source_contributes = list(EFFECT_BUCKLED = TRUE)
	holds_while = CHECK(/datum/om/check/in_range, 0)
	/// Set by buckle_mob() immediately before it calls om_link(), since
	/// on_link()'s signature has no room for the `forced` flag; read and
	/// cleared here.
	var/pending_forced = FALSE

/datum/om/relation/buckled_to/on_link(mob/living/source, atom/movable/target, datum/om/edge/edge)
	if(!istype(source) || !istype(target))
		return
	source.facing_dir = null
	source.set_dir(target.buckle_dir ? target.buckle_dir : target.dir)
	source.update_canmove()
	source.update_floating(source.Check_Dense_Object())
	if(target.riding_datum)
		rel_set(target.riding_datum, nameof(/datum/riding::ridden), target)
		target.riding_datum.handle_vehicle_offsets()
	source.update_water()
	target.post_buckle_mob(source)
	source.throw_alert("buckled", /atom/movable/screen/alert/restrained/buckled, new_master = target)

/datum/om/relation/buckled_to/on_unlink(mob/living/source, atom/movable/target, datum/om/edge/edge)
	if(istype(source) && !QDELETED(source))
		source.set_anchored(initial(source.anchored))
		source.update_canmove()
		source.update_floating(source.Check_Dense_Object())
		source.clear_alert("buckled")
		source.update_water()
	if(istype(target) && !QDELETED(target))
		if(target.riding_datum)
			if(istype(source))
				target.riding_datum.restore_position(source)
			target.riding_datum.handle_vehicle_offsets()
		target.post_buckle_mob(istype(source) ? source : null)

/// grab item -> the mob it grabs. No view fields (OM relations step 3):
/// the edge IS the state: GRAB_TARGET(G) and GRABBED_BY(M) read it, and the
/// assailant is simply the grab item's holder (GRAB_ASSAILANT(G)). on_target_delete = OM_END_DELETE_OTHER fixes a
/// real dangling-reference bug the hand-rolled version had: /obj/item/grab's
/// own Destroy() only ever cleaned up the affecting-mob side, so hard-deleting
/// the grabbed mob (it isn't in the grab item's contents -- the item lives in
/// the assailant's hand) left the grab item's `affecting` pointing at a
/// QDELETED mob indefinitely. Now the grab item itself is deleted the instant
/// its target is, which also matches DROPDEL's "this item doesn't outlive the
/// thing it's for" intent.
/datum/om/relation/grabbing
	name = "grab"
	source_single = TRUE
	on_target_delete = OM_END_DELETE_OTHER

/datum/om/relation/grabbing/on_link(obj/item/grab/source, mob/living/target, datum/om/edge/edge)
	if(!istype(source) || !istype(target))
		return
	var/mob/living/carbon/human/assailant = source?.grab_assailant()
	target.reveal(span_warning("You are revealed as [assailant] grabs you."))
	if(!assailant)
		return
	assailant.reveal(span_warning("You reveal yourself as you grab [target]."))
	// If the assailant is also currently grabbed by their new victim, both
	// grabs enter "dancing" (facing each other, e.g. a wrestling clinch).
	for(var/obj/item/grab/G in assailant?.grabbed_by_list())
		if(G?.grab_assailant() == target && G?.grab_target() == assailant)
			G.dancing = TRUE
			G.adjust_position()
			source.dancing = TRUE
	if(assailant?.pulling_target() == target)
		assailant.stop_pulling()

/datum/om/relation/grabbing/on_unlink(obj/item/grab/source, mob/living/target, datum/om/edge/edge)
	if(istype(target) && !QDELETED(target))
		animate(target, pixel_x = initial(target.pixel_x), pixel_y = initial(target.pixel_y), 4, 1, LINEAR_EASING)
		target.reset_plane_and_layer()

/// An atom/movable (almost always a mob, but a wheelchair also puts itself in
/// as source -- relaymove(), stool_bed_chair_nest/wheelchair.dm) -> the
/// atom/movable it is pulling. Both sides are exclusive (source_single/
/// target_single with the default OM_REL_REPLACE), so a new puller taking
/// something automatically drops whoever pulled it before -- closing a latent
/// bug the hand-rolled version had, where a second puller's start_pulling()
/// overwrote pulledby without the first puller's own `pulling` var ever being
/// cleared. `pulling`/`pulledby` are gone entirely now (OM relations step 6):
/// PULLING()/PULLED_BY() (om.dm) read the edge directly, so there is no
/// stored field left on either side to desync. holds_while = in_range(1)
/// replaces the hand-rolled "Break pulling if we are too far to pull now"
/// check that used to live in /atom/movable/Move() (atoms_movable.dm).
/datum/om/relation/pulling
	name = "pull"
	source_single = TRUE
	target_single = TRUE
	holds_while = CHECK(/datum/om/check/in_range, 1)

/datum/om/relation/pulling/on_link(atom/movable/source, atom/movable/target, datum/om/edge/edge)
	if(!istype(source) || !istype(target))
		return
	if(ismob(source))
		var/mob/M = source
		changed(M, CHANGE_MOB_STATUS)
		PUBLISH_CHANGE(M, MOB_KEY_STATUS)
		if(M.pullin)
			M.pullin.icon_state = "pull1"
	if(ismob(target))
		var/mob/pulled = target
		pulled.inertia_dir = 0

/datum/om/relation/pulling/on_unlink(atom/movable/source, atom/movable/target, datum/om/edge/edge)
	if(istype(source) && !QDELETED(source) && ismob(source))
		var/mob/M = source
		changed(M, CHANGE_MOB_STATUS)
		PUBLISH_CHANGE(M, MOB_KEY_STATUS)
		if(M.pullin)
			M.pullin.icon_state = "pull0"

// ---- Live links that used to be weak-reference vars (migration track 1c) ----

/// A bluespace radio -> the telecomms receiver (or all-in-one) it transmits
/// to. BS_TX_TARGET(radio) / BS_TX_RADIOS(machine). The receiver only accepts
/// bluespace signals from its BS_TX_RADIOS.
/datum/om/relation/bluespace_tx_to
	name = "bluespace transmitter link"
	source_single = TRUE

/// A bluespace radio -> the telecomms broadcaster (or all-in-one) it receives
/// from. BS_RX_SOURCE(radio) / BS_RX_RADIOS(machine): the machine forces its
/// broadcasts onto those radios.
/datum/om/relation/bluespace_rx_from
	name = "bluespace receiver link"
	source_single = TRUE

/// A ghost -> the movable it is following. FOLLOWING(ghost) and
/// FOLLOWERS(target) (om.dm) read the edge; the ghost also orbits the target
/// (code/game/orbit.dm), which is what moves it along.
/datum/om/relation/following
	name = "following"
	source_single = TRUE

/// A cortical borer -> the human host it has infested. BORER_HOST(borer) and
/// BORER_OF(human) (om.dm) read the edge. The hooks keep the borer in the
/// head organ's implants list, so every teardown path (detatch(),
/// leave_host(), the organ being removed, either end deleted) agrees.
/datum/om/relation/host_of
	name = "borer host"
	source_single = TRUE
	target_single = TRUE

/datum/om/relation/host_of/on_link(mob/living/simple_mob/animal/borer/source, mob/living/carbon/human/target, datum/om/edge/edge)
	if(!istype(source) || !istype(target))
		return
	var/obj/item/organ/external/head = target.get_organ(BP_HEAD)
	if(head)
		LAZYADD(head.implants, source)

/datum/om/relation/host_of/on_unlink(mob/living/simple_mob/animal/borer/source, mob/living/carbon/human/target, datum/om/edge/edge)
	if(istype(target))
		var/obj/item/organ/external/head = target.get_organ(BP_HEAD)
		if(head)
			LAZYREMOVE(head.implants, source)

// ---------------------------------------------------------------- bundles

