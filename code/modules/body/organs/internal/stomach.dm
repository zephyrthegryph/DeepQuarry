/obj/item/organ/internal/stomach
	name = "stomach"
	icon_state = "stomach"
	organ_tag = O_STOMACH
	parent_organ = BP_GROIN

	unacidable = TRUE	// Don't melt when holding your acid, dangit.

	var/acidtype = REAGENT_ID_STOMACID	// Incase you want some stomach organ with, say, polyacid instead, or sulphuric.
	var/max_acid_volume = 30

CAPABILITIES(/obj/item/organ/internal/stomach)
	configure(reagents(volume = 30))

/obj/item/organ/internal/stomach/handle_organ_proc_special(cycles)
	if(owner && ishuman(owner))
		if(reagents)
			if(reagents.total_volume + 2 < max_acid_volume && prob(20))
				reagents.add_reagent(acidtype, rand(1,2))

		if(is_broken() && prob(1))
			owner.custom_pain("There's a twisting pain in your abdomen!",1)
			owner.vomit(FALSE, TRUE)

/obj/item/organ/internal/stomach/handle_germ_effects(cycles)
	. = ..() //Up should return an infection level as an integer
	if(!.) return

	//Bacterial Gastroenteritis
	if (. >= 1)
		if(prob(1))
			owner.custom_pain("There's a twisting pain in your abdomen!",1)
			owner.apply_effect(2, AGONY, 0)
	if (. >= 2)
		if(prob(1) && owner.injury_load(INJURY_CATEGORY_TOXIC) < owner.get_endurance()*0.2)
			owner.injure(INJURY_TOXIN, 3, flags = INJURE_SILENT)
			owner.vomit(FALSE, TRUE)

/obj/item/organ/internal/stomach/xeno
	color = "#555555"
	acidtype = REAGENT_ID_PACID

/obj/item/organ/internal/stomach/machine
	name = "reagent cycler"
	icon_state = "cycler"
	organ_tag = O_CYCLER

	robotic = ORGAN_ROBOT

	acidtype = REAGENT_ID_SACID

	organ_verbs = list(/mob/living/carbon/human/proc/reagent_purge, /mob/living/carbon/human/proc/synth_reag_toggle) // +

/* // Removal - normal chem processing
		if(ishuman(owner))
			var/mob/living/carbon/human/H = owner

			if(H.ingested?.total_volume && H.bloodstr)
				H.ingested.trans_to_holder(H.bloodstr, rand(2,5))
*/

// When this organ's organ_tick() has nothing to do: the organ clock may park (/obj/item/organ/proc/life_step_idle()).
/// The acid top-up waits for the organ clock to run for something else; a broken stomach keeps it running.
/obj/item/organ/internal/stomach/life_step_idle()
	return ..() && !is_broken()

/// A reagent cycler sheds heat every step.
/obj/item/organ/internal/stomach/machine/life_step_idle()
	return FALSE
