// Object-model core: the standard library of table rows
// (doc/rewrite/object_model_core.md, "Library"). Mob Life uses the clocks,
// the incapacitation statuses and suspension (doc/rewrite/life_on_om.md).

/proc/om_library_clocks()
	return list(
		CLOCK_BIO = list("min" = 0, "max" = 10),
		CLOCK_MACHINE = list("min" = 0, "max" = 10),
		CLOCK_CHEM = list("min" = 0, "max" = 10),
	)

/// A mob status row (status.dm): timed, unit LIFE_CYCLE, raising CHANGE_MOB_STATUS on start and end,
/// plus `fields`.
/proc/om_mob_status_row(list/fields)
	. = list("kind" = OM_EFFECT_STATUS, "combine" = COMBINE_ANY, "stacking" = STACKING_MAX, "channel" = CHANGE_MOB_STATUS, "unit" = LIFE_CYCLE, "entity_type" = /mob)
	for(var/key in fields)
		.[key] = fields[key]

/proc/om_library_effects()
	return list(
		// Mob statuses (status.dm; doc/rewrite/life_on_om.md §7): timed, in units of LIFE_CYCLE.
		// Every field is declared here: immunity, veto signal, presentation and hooks.
		EFFECT_STUNNED = om_mob_status_row(list("immunity" = EFFECT_IMMUNE_STUN, "scaled" = TRUE, "signal" = COMSIG_LIVING_STATUS_STUN, "alert" = "stunned", "alert_type" = /atom/movable/screen/alert/stunned, "indicator" = "stunned",
			"on_increase" = /mob/proc/status_clear_facing, "on_start" = /mob/proc/status_incapacitation_changed, "on_end" = /mob/proc/status_incapacitation_changed)),
		EFFECT_WEAKENED = om_mob_status_row(list("immunity" = EFFECT_IMMUNE_WEAKEN, "scaled" = TRUE, "signal" = COMSIG_LIVING_STATUS_WEAKEN, "alert" = "weakened", "alert_type" = /atom/movable/screen/alert/weakened, "indicator" = "weakened",
			"on_increase" = /mob/proc/status_clear_facing, "on_start" = /mob/proc/status_knocked_down, "on_end" = /mob/proc/status_incapacitation_changed)),
		EFFECT_PARALYZED = om_mob_status_row(list("immunity" = EFFECT_IMMUNE_PARALYZE, "scaled" = TRUE, "signal" = COMSIG_LIVING_STATUS_PARALYZE, "alert" = "paralyzed", "alert_type" = /atom/movable/screen/alert/paralyzed, "indicator" = "paralysis",
			"on_increase" = /mob/proc/status_clear_facing, "on_start" = /mob/proc/status_passed_out, "on_end" = /mob/proc/status_incapacitation_changed)),
		EFFECT_SLEEPING = om_mob_status_row(list("scaled" = TRUE, "signal" = COMSIG_LIVING_STATUS_SLEEP, "alert" = "asleep", "alert_type" = /atom/movable/screen/alert/asleep, "indicator" = "sleeping",
			"on_increase" = /mob/proc/status_clear_facing, "on_start" = /mob/proc/status_incapacitation_changed, "on_end" = /mob/proc/status_incapacitation_changed)),
		EFFECT_CONFUSED = om_mob_status_row(list("scaled" = TRUE, "alert" = "confused", "alert_type" = /atom/movable/screen/alert/confused, "indicator" = "confused")),
		EFFECT_BLINDED = om_mob_status_row(list("scaled" = TRUE, "signal" = COMSIG_LIVING_STATUS_BLIND, "indicator" = "blinded", "on_end" = /mob/proc/status_sight_returned)),
		EFFECT_BLURRY = om_mob_status_row(list("rate" = 1)),
		EFFECT_NEARSIGHTED = om_mob_status_row(list("rate" = 1)),
		EFFECT_DEAFENED = om_mob_status_row(list("on_start" = /mob/proc/status_deafness_started, "on_end" = /mob/proc/status_deafness_ended)),
		EFFECT_STUTTERING = om_mob_status_row(list("rate" = 1)),
		EFFECT_MUTED = om_mob_status_row(list("rate" = 1)),
		EFFECT_DRUGGED = om_mob_status_row(list("alert" = "high", "alert_type" = /atom/movable/screen/alert/high)),
		EFFECT_SLURRING = om_mob_status_row(list("rate" = 1)),
		EFFECT_DROWSY = om_mob_status_row(list("rate" = 1)),
		EFFECT_HALLUCINATING = om_mob_status_row(list("rate" = 2)),
		// Dizziness and jitters are 0-1000 points: 3 wear off per cycle, 15 while resting.
		EFFECT_DIZZY = om_mob_status_row(list("rate" = 3, "rate_resting" = 15, "max_units" = 1000, "immunity" = EFFECT_IMMUNE_DIZZY,
			"on_start" = /mob/proc/status_dizzy_started, "on_end" = /mob/proc/status_dizzy_ended)),
		EFFECT_JITTERY = om_mob_status_row(list("rate" = 3, "rate_resting" = 15, "max_units" = 1000, "immunity" = EFFECT_IMMUNE_JITTER,
			"on_start" = /mob/proc/status_jittery_started, "on_end" = /mob/proc/status_jittery_ended)),
		// Status immunities: gaining one ends the statuses that name it. Held by mob type decls,
		// mutations and godmode.
		EFFECT_IMMUNE_STUN = list("combine" = COMBINE_ANY, "channel" = CHANGE_MOB_STATUS),
		EFFECT_IMMUNE_WEAKEN = list("combine" = COMBINE_ANY, "channel" = CHANGE_MOB_STATUS),
		EFFECT_IMMUNE_PARALYZE = list("combine" = COMBINE_ANY, "channel" = CHANGE_MOB_STATUS),
		EFFECT_IMMUNE_DIZZY = list("combine" = COMBINE_ANY, "channel" = CHANGE_MOB_STATUS),
		EFFECT_IMMUNE_JITTER = list("combine" = COMBINE_ANY, "channel" = CHANGE_MOB_STATUS),
		// Godmode: no harm reaches the entity; it holds the incapacitation immunities while on.
		EFFECT_GODMODE = list("combine" = COMBINE_ANY, "channel" = CHANGE_MOB_STATUS, "implies" = list(EFFECT_IMMUNE_STUN, EFFECT_IMMUNE_WEAKEN, EFFECT_IMMUNE_PARALYZE)),
		EFFECT_BUCKLED = list("combine" = COMBINE_ANY, "channel" = CHANGE_MOB_STATUS),
		EFFECT_SLOWED = list("combine" = COMBINE_SUM, "channel" = CHANGE_MOB_MOVEMENT),
		// Composites: defined from other effects, no contributions of their own.
		EFFECT_CAN_MOVE = list("expr" = NOT_OF(ANY_OF(EFFECT_STUNNED, EFFECT_WEAKENED, EFFECT_PARALYZED, EFFECT_BUCKLED)), "channel" = CHANGE_MOB_CAN_MOVE),
		EFFECT_CAN_ACT = list("expr" = NOT_OF(ANY_OF(EFFECT_STUNNED, EFFECT_WEAKENED, EFFECT_PARALYZED))),
		// Stat sums and factors.
		EFFECT_ARMOR_MELEE = list("combine" = COMBINE_SUM),
		EFFECT_ARMOR_BULLET = list("combine" = COMBINE_SUM),
		EFFECT_ARMOR_HEAT = list("combine" = COMBINE_SUM),
		EFFECT_INSULATION = list("combine" = COMBINE_MAX, "default" = 0),
		EFFECT_MOVE_SPEED = list("combine" = COMBINE_MULTIPLY),
		EFFECT_POWER_DRAW = list("combine" = COMBINE_SUM),
		EFFECT_HUD_VITALS = list("combine" = COMBINE_ANY),
		// Grant kinds.
		GRANT_ABILITY = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_LANGUAGE = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_VERB = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_ACCESS = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_TRAIT = list("combine" = COMBINE_SUM_PER_KEY),
	)

// ---------------------------------------------------------------- relations

/// item -> the container it is in.
/datum/om/relation/contained_in
	name = "container"
	source_single = TRUE

/// item -> the mob wearing it.
/datum/om/relation/worn_by
	name = "wearer"
	source_single = TRUE

// A machine's occupant is a slot (/datum/om/relation/slot/occupant,
// containment.md §10), not a relation declared here: read it with SLOT_ITEM().

/// mob -> what it is buckled to. `buckled`/`buckled_mobs` are gone (OM
/// relations step 6): there is no stored field on either side any more --
/// BUCKLED()/BUCKLED_MOBS() (om.dm) read the edge directly, so this relation
/// no longer has any view state to keep in sync, only the real side effects
/// below (direction/canmove/floating/water, riding offsets, the buckled
/// alert, the buckle signal).
/// break_if drops the edge outright (not just its EFFECT_BUCKLED contribution)
/// the moment the mob ends up off the buckled object's tile, e.g. a forced
/// move that didn't go through handle_buckled_mob_movement().
/datum/om/relation/buckled_to
	name = "buckle"
	source_single = TRUE
	source_contributes = list(EFFECT_BUCKLED = TRUE)
	break_if = CHECK(/datum/om/check/in_range, 0)
	/// Set by buckle_mob() immediately before it calls om_link(), since
	/// on_link()'s signature has no room for the `forced` flag; read and
	/// cleared here.
	var/pending_forced = FALSE

/datum/om/relation/buckled_to/on_link(mob/living/source, atom/movable/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(!istype(source) || !istype(target))
		return
	var/forced = pending_forced
	source.facing_dir = null
	source.set_dir(target.buckle_dir ? target.buckle_dir : target.dir)
	source.update_canmove()
	source.update_floating(source.Check_Dense_Object())
	if(target.riding_datum)
		target.riding_datum.ridden = target
		target.riding_datum.handle_vehicle_offsets()
	source.update_water()
	target.post_buckle_mob(source)
	SEND_SIGNAL(target, COMSIG_MOVABLE_BUCKLE, source, forced)
	source.throw_alert("buckled", /atom/movable/screen/alert/restrained/buckled, new_master = target)

/datum/om/relation/buckled_to/on_unlink(mob/living/source, atom/movable/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(source) && !QDELETED(source))
		source.anchored = initial(source.anchored)
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
	SHOULD_NOT_SLEEP(TRUE)
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
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(target) && !QDELETED(target))
		animate(target, pixel_x = initial(target.pixel_x), pixel_y = initial(target.pixel_y), 4, 1, LINEAR_EASING)
		target.reset_plane_and_layer()

/// mob -> stasis machine. Inhibits the occupant's biological clock while the machine is powered.
/datum/om/relation/stasis_occupant
	name = "stasis bed"
	source_single = TRUE
	target_single = TRUE
	conflict = OM_REL_REFUSE
	active_if = /datum/om/check/powered
	include = list(/datum/om/bundle/stasis)

/// An atom/movable (almost always a mob, but a wheelchair also puts itself in
/// as source -- relaymove(), stool_bed_chair_nest/wheelchair.dm) -> the
/// atom/movable it is pulling. Both sides are exclusive (source_single/
/// target_single with the default OM_REL_REPLACE), so a new puller taking
/// something automatically drops whoever pulled it before -- closing a latent
/// bug the hand-rolled version had, where a second puller's start_pulling()
/// overwrote pulledby without the first puller's own `pulling` var ever being
/// cleared. `pulling`/`pulledby` are gone entirely now (OM relations step 6):
/// PULLING()/PULLED_BY() (om.dm) read the edge directly, so there is no
/// stored field left on either side to desync. break_if = in_range(1)
/// replaces the hand-rolled "Break pulling if we are too far to pull now"
/// check that used to live in /atom/movable/Move() (atoms_movable.dm).
/datum/om/relation/pulling
	name = "pull"
	source_single = TRUE
	target_single = TRUE
	break_if = CHECK(/datum/om/check/in_range, 1)

/datum/om/relation/pulling/on_link(atom/movable/source, atom/movable/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(!istype(source) || !istype(target))
		return
	if(ismob(source))
		var/mob/M = source
		om_changed(M, CHANGE_MOB_STATUS)
		if(M.pullin)
			M.pullin.icon_state = "pull1"
	if(ismob(target))
		var/mob/pulled = target
		pulled.inertia_dir = 0

/datum/om/relation/pulling/on_unlink(atom/movable/source, atom/movable/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(source) && !QDELETED(source) && ismob(source))
		var/mob/M = source
		om_changed(M, CHANGE_MOB_STATUS)
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

/// A cyborg gripper -> the item it is wrapping (held out of one of its pockets).
/// GRIPPER_HELD(gripper). The item leaving (deleted) lets go of it.
/datum/om/relation/gripper_holding
	name = "gripper hold"
	source_single = TRUE
	target_single = TRUE

/// A mob -> the UAV it is flying through a UAV control program. UAV_MASTERS(uav)
/// hear what the UAV hears and can move it.
/datum/om/relation/uav_master
	name = "UAV control"

/// A stasis modifier -> what holds the mob in that stasis (a bag, pod or NIF).
/// STASIS_SOURCE(modifier). Stasis applied without a source (admin) has no edge.
/datum/om/relation/stasis_held_by
	name = "stasis source"
	source_single = TRUE

/// consumer -> power source.
/datum/om/relation/powered_by
	name = "power source"
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
	SHOULD_NOT_SLEEP(TRUE)
	if(!istype(source) || !istype(target))
		return
	var/obj/item/organ/external/head = target.get_organ(BP_HEAD)
	if(head)
		LAZYADD(head.implants, source)

/datum/om/relation/host_of/on_unlink(mob/living/simple_mob/animal/borer/source, mob/living/carbon/human/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(target))
		var/obj/item/organ/external/head = target.get_organ(BP_HEAD)
		if(head)
			LAZYREMOVE(head.implants, source)

// ---------------------------------------------------------------- bundles

/datum/om/bundle/powered_machine
	derived = list(
		DERIVE("powered_ok", ALL_OF(/datum/om/check/powered, /datum/om/check/not_broken), CHANGE_MACHINE_POWERED_OK),
	)
	checks = list(
		"machine_usable" = ALL_OF(/datum/om/check/powered, /datum/om/check/not_broken, /datum/om/check/anchored),
	)

/datum/om/bundle/storage
	derived = list(
		DERIVE_COUNT("contents_count", /datum/om/relation/contained_in, CHANGE_CONTENTS),
		DERIVE_SUM("contents_weight", /datum/om/relation/contained_in, FROM_VAR("w_class"), CHANGE_ITEM_TOTAL_MASS),
	)

/datum/om/bundle/powered_vehicle
	include = list(/datum/om/bundle/powered_machine)

/// For relations: the source (occupant) has its biological clock stopped.
/datum/om/bundle/stasis
	source_contributes = list(EFFECT_CLOCK_BIO_INHIBIT = 1)

/datum/om/bundle/hud_on_vitals
	behaviours = list(/datum/om/behaviour/hud_on_vitals)
	self_effects = list(EFFECT_HUD_VITALS = TRUE)

/datum/om/bundle/ui_live
	ui = list(
		list("watch" = 0xFFFFFF, "stream_rates" = list()),
	)

/// Refreshes the vitals HUD when vitals change (calls E.om_refresh_vitals_hud()).
/datum/om/behaviour/hud_on_vitals
	name = "om: vitals hud"
	lane = LANE_PRESENTATION
	wake_on = CHANGE_MOB_VITALS | CHANGE_MOB_STAT

/datum/om/behaviour/hud_on_vitals/on_wake(datum/E, changes)
	E.om_refresh_vitals_hud()

/datum/proc/om_refresh_vitals_hud()
	return
