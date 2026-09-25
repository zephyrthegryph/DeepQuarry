// Life stages (doc/rewrite/life_on_om.md). One concern of a living mob's upkeep.
//
// A stage is a flyweight per type: per-mob state lives on the mob, its body or a component, never
// on the stage. Every call receives the mob as `self` and the frame as `ctx`.
//
// Families and variants. A family is one concern (breathing, environment, HUD, ...). Its root is a
// direct child of /datum/om/stage/life (or of the trait category). A family may have variants for
// particular mob types: the variant path mirrors the mob path under the family root, and its `of`
// names the mob type it serves, for example
//	/datum/om/stage/life/environment               of = /mob/living
//	/datum/om/stage/life/environment/carbon/human  of = /mob/living/carbon/human
// A mob gets the variant whose `of` sits deepest in its inheritance (resolved once per mob type
// by the pipeline), and a variant's `..()` reaches the variant of the nearest ancestor mob type,
// as the old handle_* override chains did.

/datum/om/stage/life
	category = /datum/om/stage/life
	pipeline = /datum/om/pipeline/life
	of = /mob/living
	wake_on = CHANGE_MOB_LOC | CHANGE_MOB_CONDITIONS
	/// LIFE_SET_* flags of the Life sequences that include this family. Read from the variant.
	var/life_sets = LIFE_SET_LIVING

/// Only the families of the mob's Life sequence (the silicons never ran the living core).
/datum/om/stage/life/applies(mob/living/self)
	return (life_sets & self.life_set)

// --- The frame --------------------------------------------------------------------------------

/// A Life frame: dt is LIFE_CYCLE_SECONDS; facts are the old gates.
/datum/om/frame/life
	facts = list(
		// Not transforming and somewhere: the old `if(transforming) return` / `if(!loc) return`.
		// Transforming raises no channel, so a stage it skips stays awake.
		"placed" = list(/datum/om/frame/life/proc/fact_placed, 0),
		"alive" = list(/datum/om/frame/life/proc/fact_alive, CHANGE_MOB_STAT),
		// Set by the status stage (its update_status() result); alive when read without it.
		"status_ok" = list(/datum/om/frame/life/proc/fact_alive, CHANGE_MOB_STAT),
		// No biology step this frame (stasis): begin() advances the stasis counter once.
		"in_stasis" = list(/datum/om/frame/life/proc/fact_in_stasis, 0),
		// The air the mob sits in: turf air, belly air or null.
		"environment" = list(/datum/om/frame/life/proc/fact_environment, CHANGE_MOB_LOC),
	)
	var/stasis = FALSE

/datum/om/frame/life/begin()
	var/mob/living/L = entity
	stasis = L.body ? L.body.advance_stasis() : FALSE

/datum/om/frame/life/reset()
	stasis = FALSE

/datum/om/frame/life/proc/fact_placed()
	var/mob/living/L = entity
	return L.loc && !L.transforming

/datum/om/frame/life/proc/fact_alive()
	var/mob/living/L = entity
	return L.stat != DEAD

/datum/om/frame/life/proc/fact_in_stasis()
	return stasis

/datum/om/frame/life/proc/fact_environment()
	var/mob/living/L = entity
	if(!L.loc)
		return null
	if(isbelly(L.loc))
		return L.loc.return_air_for_internal_lifeform(L)
	return L.loc.return_air()
