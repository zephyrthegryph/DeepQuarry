
/*
 * Modifiers applied by Medical sources.
 */

//See blood.dm. This makes your blood volume & raw blood volume set to 100%.
//This means (as long as you have blood) you will not suffocate. Even with no heart or lungs.
/datum/modifier/bloodpump
	name = "external blood pumping"
	desc = "Your blood flows thanks to the wonderful power of science."

	on_created_text = span_notice("You feel alive.")
	on_expired_text = span_notice("You feel.. less alive.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_PULSE_SET = PULSE_NORM)

/datum/modifier/bloodpump/check_if_valid()
	..()
	if(holder.stat == DEAD)
		src.expire()

/datum/modifier/bloodpump_corpse
	name = "forced blood pumping"
	desc = "Your blood flows thanks to the wonderful power of science."

	on_created_text = span_notice("You feel alive.")
	on_expired_text = span_notice("You feel.. less alive.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_PULSE_SET = PULSE_SLOW)
	var/mob/living/carbon/human/human_being_pumped

//The meat and
/datum/modifier/bloodpump_corpse/proc/process_blood()
	holder.process_chemicals() // Circulates chemicals throughout the body.
	if(human_being_pumped) //Specialty human procs.
		human_being_pumped.process_organs() //Things like antibiotics will work. And since we're circulating, it makes infections get worse if we don't treat them!
		om_stage_run_now(human_being_pumped, /datum/om/stage/life/heartbeat) //We can hear our own heart being pumped! This makes a pretty neat sound effect.

/datum/modifier/bloodpump_corpse/on_applied()
	if(ishuman(holder))
		human_being_pumped = holder
	return

/datum/modifier/bloodpump_corpse/check_if_valid()
	..()
	if(holder.stat != DEAD)
		src.expire()

/datum/modifier/bloodpump_corpse/expire(silent)
	human_being_pumped = null
	..()

//This INTENTIONALLY only happens on DEAD people. Alive people are metabolizing already (and can be healed quicker through things like brute packs) meaning they don't need this extra assistance!
//Why does it not make you bleed out? Because we'll let medical have a few benefits that don't come with innate downsides. It takes 2 seconds to resleeve someone. It takes a good amount of time to repair a corpse. Let's make the latter more appealing.
/datum/modifier/bloodpump_corpse/tick()
	for(var/i in 1 to 5) //It's a controlled machine. 5 pumps per tick.
		process_blood() // Circulates chemicals throughout the body.
/*
 * Modifiers caused by chemicals or organs specifically.
 */

/datum/modifier/bloodpump_corpse/cpr
	desc = "Your blood flows thanks to the wonderful power of CPR."
	// No pulse. You're acting as their pulse.
	factors = alist(BF_PULSE_SET = PULSE_NONE)

/datum/modifier/bloodpump_corpse/cpr/tick()
	var/randomization = rand(4,7) //CPR isn't perfect. You get some randomization in there.
	for(var/i in 1 to randomization)
		process_blood()

/datum/modifier/cryogelled
	name = "cryogelled"
	desc = "Your body begins to freeze."
	mob_overlay_state = "chilled"

	on_created_text = span_danger("You feel like you're going to freeze! It's hard to move.")
	on_expired_text = span_warning("You feel somewhat warmer and more mobile now.")
	stacks = MODIFIER_STACK_ALLOWED

	factors = alist(BF_SLOWDOWN = 0.1, BF_EVASION = -5, BF_ATTACK_SPEED = 1.1, BF_DISABLE_DURATION = 1.05)

/datum/modifier/clone_stabilizer
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

/datum/modifier/numbness
	name = "numbness"
	desc = "You can barely feel your body."
	hidden = TRUE
	stacks = MODIFIER_STACK_EXTEND
	factors = alist(BF_ANALGESIA = 60)

/datum/modifier/numbness/mild
	factors = alist(BF_ANALGESIA = 20)

/datum/modifier/numbness/deep
	factors = alist(BF_ANALGESIA = 150)

/// Synx venom: numbs and steadies the prey.
/datum/modifier/numbness/synx
	factors = alist(BF_ANALGESIA = 50, BF_STABILIZATION = 15)

/// A withdrawal crisis strains the liver, kidneys and spleen.
/datum/modifier/withdrawal_strain
	name = "withdrawal strain"
	hidden = TRUE
	stacks = MODIFIER_STACK_EXTEND
	factors = alist(BF_WITHDRAWAL = 0.5)

/datum/modifier/withdrawal_strain/mild
	factors = alist(BF_WITHDRAWAL = 0.5)

/datum/modifier/withdrawal_strain/moderate
	factors = alist(BF_WITHDRAWAL = 1.4)

/datum/modifier/withdrawal_strain/severe
	factors = alist(BF_WITHDRAWAL = 2.3)

/// Airborne allergens (pollen) set off the mob's allergies.
/datum/modifier/allergic_flare
	name = "allergic flare"
	hidden = TRUE
	stacks = MODIFIER_STACK_EXTEND
	factors = alist(BF_ALLERGY = 2.5)

/// A disease symptom rebuilding blood.
/datum/modifier/blood_regeneration
	name = "blood regeneration"
	hidden = TRUE
	stacks = MODIFIER_STACK_EXTEND
	factors = alist(BF_BLOOD_REGEN = 1)
