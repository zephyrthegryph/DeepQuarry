
/*
 * Modifiers applied by Medical sources.
 */

//See blood.dm. This makes your blood volume & raw blood volume set to 100%.
//This means (as long as you have blood) you will not suffocate. Even with no heart or lungs.
/datum/body_effect/bloodpump
	tick_interval = 2 SECONDS
	name = "external blood pumping"
	desc = "Your blood flows thanks to the wonderful power of science."

	on_created_text = span_notice("You feel alive.")
	on_expired_text = span_notice("You feel.. less alive.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_PULSE_SET = PULSE_NORM)

/datum/body_effect/bloodpump/on_check(mob/living/L)
	if(L.stat == DEAD)
		L.end_body_effect(type)
		return

/datum/body_effect/bloodpump_corpse
	tick_interval = 2 SECONDS
	name = "forced blood pumping"
	desc = "Your blood flows thanks to the wonderful power of science."

	on_created_text = span_notice("You feel alive.")
	on_expired_text = span_notice("You feel.. less alive.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_PULSE_SET = PULSE_SLOW)

//The meat and
/datum/body_effect/bloodpump_corpse/proc/process_blood(mob/living/L)
	L.process_chemicals() // Circulates chemicals throughout the body.
	if(ishuman(L)) //Specialty human procs.
		var/mob/living/carbon/human/human_being_pumped = L
		human_being_pumped.organs_advance(1) //Things like antibiotics will work. And since we're circulating, it makes infections get worse if we don't treat them!
		run_step_now(human_being_pumped, TYPE_PROC_REF(/mob/living/carbon/human, life_heartbeat), /datum/sequence/life) //We can hear our own heart being pumped! This makes a pretty neat sound effect.

/datum/body_effect/bloodpump_corpse/on_check(mob/living/L)
	if(L.stat != DEAD)
		L.end_body_effect(type)

//This INTENTIONALLY only happens on DEAD people. Alive people are metabolizing already (and can be healed quicker through things like brute packs) meaning they don't need this extra assistance!
//Why does it not make you bleed out? Because we'll let medical have a few benefits that don't come with innate downsides. It takes 2 seconds to resleeve someone. It takes a good amount of time to repair a corpse. Let's make the latter more appealing.
/datum/body_effect/bloodpump_corpse/on_tick(mob/living/L)
	for(var/i in 1 to 5) //It's a controlled machine. 5 pumps per tick.
		process_blood(L) // Circulates chemicals throughout the body.
/*
 * Modifiers caused by chemicals or organs specifically.
 */

/datum/body_effect/bloodpump_corpse/cpr
	desc = "Your blood flows thanks to the wonderful power of CPR."
	// No pulse. You're acting as their pulse.
	factors = alist(BF_PULSE_SET = PULSE_NONE)

/datum/body_effect/bloodpump_corpse/cpr/on_tick(mob/living/L)
	var/randomization = rand(4,7) //CPR isn't perfect. You get some randomization in there.
	for(var/i in 1 to randomization)
		process_blood(L)

/datum/body_effect/cryogelled
	name = "cryogelled"
	desc = "Your body begins to freeze."
	mob_overlay_state = "chilled"

	on_created_text = span_danger("You feel like you're going to freeze! It's hard to move.")
	on_expired_text = span_warning("You feel somewhat warmer and more mobile now.")
	stacks = MODIFIER_STACK_ALLOWED

	factors = alist(BF_SLOWDOWN = 0.1, BF_EVASION = -5, BF_ATTACK_SPEED = 1.1, BF_DISABLE_DURATION = 1.05)

/datum/body_effect/clone_stabilizer
	name = "clone stabilized"
	desc = "Your body's regeneration is highly restricted."

	on_created_text = span_danger("You feel nauseous.")
	on_expired_text = span_warning("You feel healthier.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_HEALING_RECEIVED = 0.1)


// --- Transient body-factor sources ------------------------------------------------------
// Brief effects that aren't reagents (venom bites, rotting nerves, withdrawal
// crises, allergy flares). Each is a short modifier carrying a static factor
// table; re-applying one while it runs extends it.

/datum/body_effect/numbness
	name = "numbness"
	desc = "You can barely feel your body."
	hidden = TRUE
	stacks = MODIFIER_STACK_EXTEND
	factors = alist(BF_ANALGESIA = 60)

/datum/body_effect/numbness/mild
	factors = alist(BF_ANALGESIA = 20)

/datum/body_effect/numbness/deep
	factors = alist(BF_ANALGESIA = 150)

/// Synx venom: numbs and steadies the prey.
/datum/body_effect/numbness/synx
	factors = alist(BF_ANALGESIA = 50, BF_STABILIZATION = 15)

/// A withdrawal crisis strains the liver, kidneys and spleen.
/datum/body_effect/withdrawal_strain
	name = "withdrawal strain"
	hidden = TRUE
	stacks = MODIFIER_STACK_EXTEND
	factors = alist(BF_WITHDRAWAL = 0.5)

/datum/body_effect/withdrawal_strain/mild
	factors = alist(BF_WITHDRAWAL = 0.5)

/datum/body_effect/withdrawal_strain/moderate
	factors = alist(BF_WITHDRAWAL = 1.4)

/datum/body_effect/withdrawal_strain/severe
	factors = alist(BF_WITHDRAWAL = 2.3)

/// B25: alcohol withdrawal races the heart. A forced pulse level, so the
/// heart system reads it instead of a raw `pulse` write it would overwrite.
/datum/body_effect/withdrawal_tachycardia
	name = "withdrawal tachycardia"
	hidden = TRUE
	stacks = MODIFIER_STACK_EXTEND
	factors = alist(BF_PULSE_SET = PULSE_2FAST)

/datum/body_effect/withdrawal_tachycardia/mild
	factors = alist(BF_PULSE_SET = PULSE_FAST)

/// Airborne allergens (pollen) set off the mob's allergies.
/datum/body_effect/allergic_flare
	name = "allergic flare"
	hidden = TRUE
	stacks = MODIFIER_STACK_EXTEND
	factors = alist(BF_ALLERGY = 2.5)

/// A disease symptom rebuilding blood.
/datum/body_effect/blood_regeneration
	name = "blood regeneration"
	hidden = TRUE
	stacks = MODIFIER_STACK_EXTEND
	factors = alist(BF_BLOOD_REGEN = 1)
