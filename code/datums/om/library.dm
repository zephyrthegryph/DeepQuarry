// Object-model core: the standard library of table rows
// (doc/rewrite/object_model_core.md, "Library"). Mob Life uses the clocks,
// the incapacitation statuses and suspension (doc/rewrite/life_on_om.md).

/proc/om_library_clocks()
	return list(
		CLOCK_BIO = list("min" = 0, "max" = 10),
		CLOCK_MACHINE = list("min" = 0, "max" = 10),
		CLOCK_CHEM = list("min" = 0, "max" = 10),
	)

/proc/om_library_effects()
	return list(
		// Statuses: any source makes them true; timed applies keep the longest.
		// Incapacitation. Mobs apply these through Stun()/Weaken()/Paralyse() and friends
		// (doc/rewrite/life_on_om.md §7); the effect type keeps canmove, lying and alerts in step.
		EFFECT_STUNNED = list("combine" = COMBINE_ANY, "stacking" = STACKING_MAX, "channel" = CHANGE_MOB_STATUS, "type" = /datum/om/effect/mob_incapacitation),
		EFFECT_WEAKENED = list("combine" = COMBINE_ANY, "stacking" = STACKING_MAX, "channel" = CHANGE_MOB_STATUS, "type" = /datum/om/effect/mob_incapacitation),
		EFFECT_PARALYZED = list("combine" = COMBINE_ANY, "stacking" = STACKING_MAX, "channel" = CHANGE_MOB_STATUS, "type" = /datum/om/effect/mob_incapacitation),
		EFFECT_BUCKLED = list("combine" = COMBINE_ANY, "channel" = CHANGE_MOB_STATUS),
		EFFECT_BLINDED = list("combine" = COMBINE_ANY, "stacking" = STACKING_EXTEND, "channel" = CHANGE_MOB_STATUS),
		EFFECT_MUTED = list("combine" = COMBINE_ANY, "stacking" = STACKING_EXTEND, "channel" = CHANGE_MOB_STATUS),
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

/// mob -> the seat, vehicle or machine it occupies.
/datum/om/relation/occupant_of
	name = "seat"
	source_single = TRUE
	include = list(/datum/om/bundle/occupant_seat)

/// mob -> what it is buckled to.
/datum/om/relation/buckled_to
	name = "buckle"
	source_single = TRUE
	source_contributes = list(EFFECT_BUCKLED = TRUE)

/// mob -> stasis machine. Inhibits the occupant's biological clock while the machine is powered.
/datum/om/relation/stasis_occupant
	name = "stasis bed"
	source_single = TRUE
	target_single = TRUE
	conflict = OM_REL_REFUSE
	active_if = /datum/om/check/powered
	include = list(/datum/om/bundle/stasis)

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
