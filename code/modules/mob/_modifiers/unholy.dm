/*
 * Modifiers originating from cult runes, spells, or pylons are kept here.
 */


////////// Self-Enhancing
/datum/modifier/fortify
	name = "fortified body"
	desc = "You are taking less damage from outside sources."

	on_created_text = span_critical("Your body becomes a mountain to your enemies' storm.")
	on_expired_text = span_notice("Your body softens, returning to its regular durability.")
	stacks = MODIFIER_STACK_EXTEND

	// Disables only last 25% as long.
	// 50% incoming damage.
	// Become a bigger target.
	factors = alist(BF_SLOWDOWN = 2, BF_EVASION = -20, BF_INCOMING_ALL = 0.5, BF_DISABLE_DURATION = 0.25, BF_ICON_SCALE_X = 1.2, BF_ICON_SCALE_Y = 1.2, BF_PAIN_IMMUNITY = 1)


/datum/modifier/ambush
	name = "phased"
	desc = "You are partially shifted from the material plane."

	on_created_text = span_critical("Your body pulses, before partially dematerializing.")
	on_expired_text = span_notice("Your body rematerializes fully.")

	stacks = MODIFIER_STACK_FORBID

	// 10% incoming damage. You're not all there.
	// 0% outgoing damage. Be prepared.
	// Luckily, not being all there means you're actually hard to hit with a gun.
	factors = alist(BF_EVASION = 50, BF_MELEE_DAMAGE = 0, BF_INCOMING_ALL = 0.1, BF_PAIN_IMMUNITY = 1)


/datum/modifier/ambush/on_applied()
	holder.alpha = 30
	return

// Override this for special effects when it gets removed.
/datum/modifier/ambush/on_expire()
	holder.alpha = 255
	return

////////// On-hit
/datum/modifier/deep_wounds
	name = "deep wounds"
	desc = "Your wounds are mysteriously harder to mend."

	on_created_text = span_cult("Your wounds pain you greatly.")
	on_expired_text = span_notice("Your wounds numb for a moment.")

	stacks = MODIFIER_STACK_EXTEND

	// 34% less healing.
	// 22% longer disables.
	factors = alist(BF_DISABLE_DURATION = 1.22, BF_HEALING_RECEIVED = 0.66)


////////// Auras
/datum/modifier/repair_aura //This aura does not apply modifiers to individuals in the area.
	name = "aura of repair (cult)"
	desc = "You are emitting a field of strange energy, capable of repairing occult constructs."

	on_created_text = span_cult("You begin emitting an occult repair aura.")
	on_expired_text = span_notice("The occult repair aura fades.")
	stacks = MODIFIER_STACK_EXTEND

	mob_overlay_state = "cult_aura"

/datum/modifier/repair_aura/tick()
	spawn()
		for(var/mob/living/simple_mob/construct/T in view(4,holder))
			T.occult_mend(rand(10,15), rand(10,15))

/datum/modifier/agonize //This modifier is used in an aura spell.
	name = "agonize"
	desc = "Your body is wracked with pain."

	on_created_text = span_cult("A red lightning quickly covers your body. The pain is horrendous.")
	on_expired_text = span_notice("The lightning fades, and so too does the ongoing pain.")

	stacks = MODIFIER_STACK_EXTEND

	mob_overlay_state = "red_electricity_constant"

/datum/modifier/agonize/tick()
	spawn()
		if(ishuman(holder))
			var/mob/living/carbon/human/H = holder
			H.apply_effect(20, AGONY)
			if(prob(10))
				to_chat(H, span_warning("Just make it stop!"))

////////// Target Modifier
/datum/modifier/mend_occult
	name = "occult mending"
	desc = "Your body is mending, though at what cost?"

	on_created_text = span_cult("Something haunting envelops your body as it begins to mend.")
	on_expired_text = span_notice("The cloak of unease dissipates.")

	stacks = MODIFIER_STACK_EXTEND

	mob_overlay_state = "red_electricity_constant"

/datum/modifier/mend_occult/tick()
	spawn()
		if(isliving(holder))
			var/mob/living/L = holder
			if(istype(L, /mob/living/simple_mob/construct))
				L.occult_mend(rand(5,10), rand(5,10))
			else
				L.occult_mend(2, 2)

			if(ishuman(holder))
				var/mob/living/carbon/human/H = holder

				for(var/obj/item/organ/internal/O in H.internal_organs)
					if(O.damage > 0) // Fix internal damage
						H.mend(TREAT_RESTORATION, 2, O)
					if(O.damage <= 5 && O.organ_tag == O_EYES) // Fix eyes
						H.sdisabilities &= ~BLIND

				for(var/obj/item/organ/external/O in H.organs) // Fix limbs, no matter if they are Man or Machine.
					H.mend(TREAT_RESTORATION, rand(2,6), O)

				for(var/obj/item/organ/E in H.bad_external_organs) // Fix bones
					var/obj/item/organ/external/affected = E
					if((affected.damage < affected.min_broken_damage * CONFIG_GET(number/organ_health_multiplier)) && (affected.status & ORGAN_BROKEN))
						affected.status &= ~ORGAN_BROKEN

					for(var/datum/affliction/wound/internal_bleeding/W in affected.get_wounds()) // Fix IB
						affected.remove_wound(W)
						affected.update_damages()

				H.restore_blood()
				if(!iscultist(H))
					H.apply_effect(2, AGONY)
				if(prob(10))
					to_chat(H, span_danger("It feels as though your body is being torn apart!"))

/datum/modifier/gluttonyregeneration
	name = "gluttonous regeneration"
	desc = "You are filled with an overwhelming hunger."
	mob_overlay_state = "electricity"

	on_created_text = span_critical("You feel an intense and overwhelming hunger overtake you as your body regenerates!")
	on_expired_text = span_notice("The blaze of hunger inside you has been snuffed.")
	stacks = MODIFIER_STACK_EXTEND

/datum/modifier/gluttonyregeneration/can_apply(mob/living/L)
	if(L.stat == DEAD)
		to_chat(L, span_warning("You can't be dead to consume."))
		return FALSE

	if(!L.is_sentient())
		return FALSE // Drones don't feel anything, not even hunger.

	if(L.has_modifier_of_type(/datum/modifier/berserk_exhaustion))
		to_chat(L, span_warning("You recently berserked, so you are too tired to consume."))
		return FALSE

	if(!ishuman(L)) // Only humanoids feel hunger. Totally.
		return FALSE

	else
		var/mob/living/carbon/human/H = L
		if(H.species.name == "Diona")
			to_chat(L, span_warning("You feel strange for a moment, but it passes."))
			return FALSE // Happy trees aren't affected by incredible hunger.

	return ..()

/datum/modifier/gluttonyregeneration/tick()
	spawn()
		if(ishuman(holder))
			var/mob/living/carbon/human/H = holder
			var/starting_nutrition = H.nutrition
			H.adjust_nutrition(-10)
			var/healing_amount = starting_nutrition - H.nutrition //Anything above 9 nutrition will return 10. Anything below will give 0-9. Nutrition is capped at 0.
			if(healing_amount)
				H.occult_mend(healing_amount * 0.25, healing_amount * 0.25)
				H.mend(TREAT_OXYGENATION, healing_amount * 0.25)
				H.mend(TREAT_ANTITOXIN, healing_amount * 0.25)

	..()

/// Supernatural mending knits flesh and metal alike: it applies both the
/// organic and the synthetic repair mechanism, and the body uses whichever
/// matches each part.
/mob/living/proc/occult_mend(physical, thermal)
	if(physical)
		mend(TREAT_TISSUE_REPAIR, physical)
		mend(TREAT_PLATING_REPAIR, physical)
	if(thermal)
		mend(TREAT_BURN_CARE, thermal)
		mend(TREAT_WIRING_REPAIR, thermal)
