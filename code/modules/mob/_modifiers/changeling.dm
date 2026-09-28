/datum/body_effect/changeling
	stacks = MODIFIER_STACK_FORBID
	tick_interval = 2 SECONDS
	name = "changeling"
	desc = "Changeling modifier."

	var/required_chems = 1	// Default is to require at least 1 chem unit. This does not consume it.

	var/chem_maintenance = 1	// How many chems are expended per cycle, if we are consuming chems.

	var/max_genetic_damage = 100

	var/max_stat = 0

	var/use_chems = FALSE	// Do we have an upkeep cost on chems?

	var/exterior_modifier = FALSE	// Should we be checking the origin mob for chems?

/// The changeling paying for the effect: the mob itself, or whoever applied it (exterior_modifier).
/datum/body_effect/changeling/proc/changeling_of(mob/living/L) as /mob/living
	return exterior_modifier ? L.body_effect_origin(type) : L

/datum/body_effect/changeling/on_check(mob/living/L)
	var/mob/living/ling = changeling_of(L)
	if(!ling || !ling.changeling_power(required_chems, 0, max_genetic_damage, max_stat))
		L.end_body_effect(type)

/datum/body_effect/changeling/on_tick(mob/living/L)
	if(!use_chems)
		return
	var/mob/living/ling = changeling_of(L)
	var/datum/changeling/comp = ling?.get_changeling_state()
	if(comp)
		comp.chem_charges = between(0, comp.chem_charges - chem_maintenance, comp.chem_storage)

/datum/body_effect/changeling/thermal_sight
	name = "Thermal Adaptation"
	desc = "Our eyes are capable of seeing into the infrared spectrum to accurately identify prey through walls."
	factors = alist(BF_SIGHT_FLAGS = SEE_MOBS)

	on_expired_text = span_alien("Your sight returns to what it once was.")
	stacks = MODIFIER_STACK_EXTEND

/datum/body_effect/changeling/thermal_sight/on_check(mob/living/L)
	var/mob/living/ling = changeling_of(L)
	var/datum/changeling/changeling = ling?.changeling_power(0,0,100,CONSCIOUS)
	if(!changeling?.thermal_sight)
		L.end_body_effect(type)

/datum/body_effect/changeling/thermal_sight/on_end(mob/living/L, expired)
	var/mob/living/ling = changeling_of(L)
	var/datum/changeling/changeling = ling?.changeling_power(0,0,100,CONSCIOUS)
	if(changeling)
		changeling.thermal_sight = FALSE
