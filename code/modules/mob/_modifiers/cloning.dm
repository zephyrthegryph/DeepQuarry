/*
 *	Modifier applied to newly cloned people.
 */

// Gives rather nasty downsides for awhile, making them less robust.
/datum/modifier/cloning_sickness
	name = "cloning sickness"
	desc = "You feel rather weak, having been cloned not so long ago."

	on_created_text = span_warning(span_large("You feel really weak."))
	on_expired_text = span_notice(span_large("You feel your strength returning to you."))

	// -40% max health.
	// 10% more incoming damage.
	// 30% less melee damage.
	// Stuns last 25% longer.
	// Slower.
	// 15% easier to hit.
	factors = alist(BF_SLOWDOWN = 1, BF_EVASION = -15, BF_MELEE_DAMAGE = 0.7, BF_INCOMING_ALL = 1.1, BF_DISABLE_DURATION = 1.25, BF_ENDURANCE_MULT = 0.6)

// Tracks number of deaths, one modifier added per cloning
/datum/modifier/cloned
	name = "cloned"
	desc = "You died and were cloned, and you can never forget that."

	flags = MODIFIER_GENETIC			// So it gets copied if they die and get cloned again.
	stacks = MODIFIER_STACK_ALLOWED		// Two deaths means two instances of this.

// Prevents cloning, actual effect is on the cloning machine
/datum/modifier/no_clone
	name = "Cloning Incompatibility"
	desc = "For whatever reason, you cannot be cloned."

	//WIP, but these may never be seen anyway, so *shrug
	on_created_text = span_warning("Life suddenly feels more precious.")
	on_expired_text = span_notice("Death is cheap again.")

	flags = MODIFIER_GENETIC


// Prevents borging (specifically the MMI part), actual effect is on the MMI.
/datum/modifier/no_borg
	name = "Cybernetic Incompatibility"
	desc = "For whatever reason, your brain is incompatible with direct cybernetic interfaces, such as the MMI."

	flags = MODIFIER_GENETIC

//////////////////////////////////////
//Species-Specific Cloning Modifiers//
/////////////////////////////////////

/datum/modifier/cloning_sickness/promethean
	name = "reformation sickness"
	desc = "Your core feels damaged, as you were reformed with the improper machinery."

	on_created_text = span_warning(span_large("Your core aches."))
	on_expired_text = span_notice(span_large("You feel your core's strength returning to normal."))

	// Level the incoming damage from the parent modifier. They already take 200% burn.
	// 150% incoming brute damage. Decreases the effectiveness of their 0.75 modifier.
	// 125% incoming halloss.
	// 50% less outgoing melee damage.
	// 20% slower attack speed.
	factors = alist(BF_SLOWDOWN = 1, BF_EVASION = -15, BF_ATTACK_SPEED = 1.2, BF_MELEE_DAMAGE = 0.5, BF_INCOMING_ALL = 1, BF_INCOMING_PHYSICAL = 1.5, BF_INCOMING_PAIN = 1.25, BF_DISABLE_DURATION = 1.25, BF_ENDURANCE_MULT = 0.6)


//////////////////////
//Surgical Modifiers// As of writing, limited to the 'Frankenstein' modifier.
//////////////////////

/datum/modifier/franken_sickness
	name = "surgically attached brain"
	desc = "You feel weak, as your central nervous system is still recovering from being repaired."

	on_created_text = span_warning(span_large("You feel... off, and your head hurts."))
	on_expired_text = span_notice(span_large("You feel some strength returning to you."))

	// -10% max health.
	// 10% more incoming damage.
	// 50% more halloss damage, stacking on the previous 1.1 widespread.
	// 10% less melee damage.
	// Stuns last 25% longer.
	// -10% to all healing
	// 5% easier to hit.
	// Inaccurate trait level of tile dispersion.
	factors = alist(BF_DISPERSION = 1, BF_EVASION = -5, BF_MELEE_DAMAGE = 0.9, BF_INCOMING_ALL = 1.1, BF_INCOMING_PAIN = 1.5, BF_DISABLE_DURATION = 1.25, BF_HEALING_RECEIVED = 0.9, BF_ENDURANCE_MULT = 0.9)

	stacks = MODIFIER_STACK_ALLOWED //You have somehow had the surgery done twice. Your brain is very, very fucked, but I won't say no.

/datum/modifier/franken_sickness/can_apply(mob/living/L)
	if(!ishuman(L))
		return FALSE
	if(L.isSynthetic()) //Nonhumans and Machines cannot be Frankensteined, at this time.
		return FALSE

	return ..()

/datum/modifier/franken_recovery //When Franken_Sickness expires, this will be permanently applied in its place.
	name = "neural recovery"
	desc = "You feel out of touch, as your central nervous system is still recovering from being repaired."

	on_created_text = span_warning(span_large("You feel... off. Everything is fuzzy."))
	on_expired_text = span_notice(span_large("You feel your senses returning to you."))

	// 50% more halloss damage.
	// Stuns last 25% longer.
	// 5% easier to hit.
	// Inaccurate trait level of tile dispersion.
	factors = alist(BF_DISPERSION = 1, BF_EVASION = -5, BF_INCOMING_PAIN = 1.5, BF_DISABLE_DURATION = 1.25)

	stacks = MODIFIER_STACK_ALLOWED

/datum/modifier/franken_recovery/can_apply(mob/living/L)
	if(!ishuman(L))
		return FALSE
	if(L.isSynthetic()) //Nonhumans and Machines cannot be Frankensteined, at this time.
		return FALSE

	return ..()
