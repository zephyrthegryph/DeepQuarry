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

/// mob -> the seat, vehicle or machine it occupies. target_ref_field makes
/// the core the sole writer of the machine's `occupant` var: Sleeper.dm,
/// cryo.dm, cryopod.dm, mecha.dm and the rest each used to hand-set
/// `occupant = M` on entry with no COMSIG_QDELETING hook, so hard-deleting
/// the occupant mid-occupancy (an explosion, an admin action) left `occupant`
/// pointing at a QDELETED mob until the next unrelated write happened to
/// overwrite it. The move-in/out mechanics (forceMove, UI, music, chemistry,
/// icons) stay exactly where they are in each machine -- only the bare field
/// write is now om_link()/om_unlink().
/datum/om/relation/occupant_of
	name = "seat"
	source_single = TRUE
	target_single = TRUE
	target_ref_field = "occupant"
	include = list(/datum/om/bundle/occupant_seat)

/// mob -> what it is buckled to. `source_ref_field`/`target_list_field` make the
/// core the sole writer of `buckled`/`buckled_mobs` (defs.dm, om_field_link()/
/// om_field_unlink() in relation.dm) -- on_link()/on_unlink() below are left
/// with only the real side effects (direction/canmove/floating/water, riding
/// offsets, the buckled alert, the buckle signal), never the bookkeeping.
/// break_if drops the edge outright (not just its EFFECT_BUCKLED contribution)
/// the moment the mob ends up off the buckled object's tile, e.g. a forced
/// move that didn't go through handle_buckled_mob_movement().
/datum/om/relation/buckled_to
	name = "buckle"
	source_single = TRUE
	source_contributes = list(EFFECT_BUCKLED = TRUE)
	break_if = CHECK(/datum/om/check/in_range, 0)
	source_ref_field = "buckled"
	target_list_field = "buckled_mobs"
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

/// grab item -> the mob it grabs. source_ref_field/target_list_field make the
/// core the sole writer of /obj/item/grab's `affecting` var and the grabbed
/// mob's `grabbed_by` list. on_target_delete = OM_END_DELETE_OTHER fixes a
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
	source_ref_field = "affecting"
	target_list_field = "grabbed_by"
	on_target_delete = OM_END_DELETE_OTHER

/datum/om/relation/grabbing/on_link(obj/item/grab/source, mob/living/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(!istype(source) || !istype(target))
		return
	target.reveal(span_warning("You are revealed as [source.assailant] grabs you."))
	source.assailant?.reveal(span_warning("You reveal yourself as you grab [target]."))
	// If the assailant is also currently grabbed by their new victim, both
	// grabs enter "dancing" (facing each other, e.g. a wrestling clinch).
	if(source.assailant?.grabbed_by)
		for(var/obj/item/grab/G in source.assailant.grabbed_by)
			if(G.assailant == target && G.affecting == source.assailant)
				G.dancing = TRUE
				G.adjust_position()
				source.dancing = TRUE
	if(source.assailant?.pulling == target)
		source.assailant.stop_pulling()

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

/// mob -> the atom/movable it is pulling. Both sides are exclusive
/// (source_single/target_single with the default OM_REL_REPLACE), so a new
/// puller taking something automatically drops whoever pulled it before --
/// closing a latent bug the hand-rolled version had, where a second puller's
/// start_pulling() overwrote pulledby without the first puller's own
/// `pulling` var ever being cleared. break_if = in_range(1) replaces the
/// hand-rolled "Break pulling if we are too far to pull now" check that used
/// to live in /atom/movable/Move() (atoms_movable.dm).
/datum/om/relation/pulling
	name = "pull"
	source_single = TRUE
	target_single = TRUE
	source_ref_field = "pulling"
	target_ref_field = "pulledby"
	break_if = CHECK(/datum/om/check/in_range, 1)

/datum/om/relation/pulling/on_link(mob/source, atom/movable/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(!istype(source) || !istype(target))
		return
	om_changed(source, CHANGE_MOB_STATUS)
	if(source.pullin)
		source.pullin.icon_state = "pull1"
	if(ismob(target))
		var/mob/pulled = target
		pulled.inertia_dir = 0

/datum/om/relation/pulling/on_unlink(mob/source, atom/movable/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(source) && !QDELETED(source))
		om_changed(source, CHANGE_MOB_STATUS)
		if(source.pullin)
			source.pullin.icon_state = "pull0"

/// implant -> the external organ it is embedded in. source_ref_field/
/// target_list_field make the core the sole writer of the implant's `part`
/// and the organ's `implants` list; on_link()/on_unlink() keep only the
/// `imp_in` (host mob) side effect, since it has no reverse list of its own
/// to double-check against. Previously both sides were hand-maintained
/// (/obj/item/implant/Destroy() and /obj/item/organ/external/Destroy() each
/// cleaned up their own half); now hard-deleting either one tears the whole
/// link down automatically, including `imp_in`, which used to only get
/// cleared by the organ's Destroy() -- so directly hard-deleting the host mob
/// without going through organ removal left `imp_in` dangling.
/datum/om/relation/implanted_in
	name = "implant site"
	source_single = TRUE
	source_ref_field = "part"
	target_list_field = "implants"

/datum/om/relation/implanted_in/on_link(obj/item/implant/source, obj/item/organ/external/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(source) && istype(target))
		source.imp_in = target.owner

/datum/om/relation/implanted_in/on_unlink(obj/item/implant/source, obj/item/organ/external/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(source) && !QDELETED(source))
		source.imp_in = null

/// consumer -> power source.
/datum/om/relation/powered_by
	name = "power source"
	source_single = TRUE

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

/datum/om/bundle/occupant_seat
	derived = list(
		DERIVE_COUNT("occupants", /datum/om/relation/occupant_of, CHANGE_MACHINE_OCCUPANT),
	)
	checks = list(
		"seat_free" = NOT_OF(CHECK(/datum/om/check/derived_true, "occupants")),
	)

/datum/om/bundle/powered_vehicle
	include = list(/datum/om/bundle/powered_machine, /datum/om/bundle/occupant_seat)

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
