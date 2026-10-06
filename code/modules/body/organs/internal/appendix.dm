/obj/item/organ/internal/appendix
	name = "appendix"
	icon_state = "appendix"
	parent_organ = BP_GROIN
	organ_tag = "appendix"
	var/inflamed = 0
	var/inflame_progress = 0

/mob/living/carbon/human/proc/appendicitis()
	// The template is detached and unreferenced once the body holds its copy.
	return force_contagion(new /datum/affliction/contagion/appendicitis)

/*
/obj/item/organ/internal/appendix/organ_tick(cycles)
	..()

	if(!inflamed || !owner)
		return

	if(++inflame_progress > 200)
		++inflamed
		inflame_progress = 0

	if(inflamed == 1)
		if(prob(5))
			to_chat(owner, span_warning("You feel a stinging pain in your abdomen!"))
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "winces slightly.", check_stat = TRUE)
	if(inflamed > 1)
		if(prob(3))
			to_chat(owner, span_warning("You feel a stabbing pain in your abdomen!"))
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "winces painfully.", check_stat = TRUE)
			owner.injure(INJURY_TOXIN, 1, flags = INJURE_SILENT)
	if(inflamed > 2)
		if(prob(1))
			owner.vomit()
	if(inflamed > 3)
		if(prob(1))
			to_chat(owner, span_danger("Your abdomen is a world of pain!"))
			owner.status_at_least(EFFECT_WEAKENED, 10)

			var/obj/item/organ/external/groin = owner.get_organ(BP_GROIN)
			owner.injure(INJURY_TOXIN, 25, flags = INJURE_SILENT)
			groin.add_wound(new /datum/affliction/wound/internal_bleeding(groin, 20))
			groin.update_damages()
			inflamed = 1
*/
/obj/item/organ/internal/appendix/removed()
	if(inflamed)
		icon_state = "[initial(icon_state)]inflamed"
		name = "inflamed appendix"
	..()

// When this organ's organ_tick() has nothing to do: the organ clock may park (/obj/item/organ/proc/life_step_idle()).
/obj/item/organ/internal/appendix/life_step_idle()
	return ..() && !inflamed
