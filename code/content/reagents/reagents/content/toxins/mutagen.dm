/datum/reagent/mutagen
	name = REAGENT_MUTAGEN
	id = REAGENT_ID_MUTAGEN
	scannable = SCANNABLE_ADVANCED
	description = "Might cause unpredictable mutations. Keep away from children."
	taste_description = "slime"
	taste_mult = 0.9
	reagent_state = LIQUID
	color = "#13BC5E"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/mutagen/affect_touch(mob/living/carbon/M, alien, removed)
	if(prob(33))
		affect_blood(M, alien, removed)

/datum/reagent/mutagen/affect_ingest(mob/living/carbon/M, alien, removed)
	if(prob(67))
		affect_blood(M, alien, removed)

/datum/reagent/mutagen/affect_blood(mob/living/carbon/M, alien, removed)

	if(HAS_SYNTHETIC_BIOLOGY(M))
		return

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(alien == IS_SLIME && prob(25))
			var/color_shift = rand(-100, 100)
			after(H, 1 TICK, TYPE_PROC_REF(/mob/living/carbon/human, slime_color_shift), with = list(color_shift))
		if(H.species.flags & NO_DNA)
			return

//The original coder comment here wanted it to be "Approx. one mutation per 10 injected/20 ingested/30 touching units"
//The issue was, it was removed (.2) multiplied by .1, which resulted in a .02% chance per tick to have a mutation occur. Or more accurately, 5000 injected for a single mutation.
//To honor their original idea, let's keep it as 10/20/30 as they wanted... For the most part.

	if(M.dna)
		if(prob(removed * 10)) // Removed is .2 per tick. Multiplying it by 10 makes it a 2% chance per tick. 10 units has 50 ticks, so 10 units injected should give a single good/bad mutation.
			if(prob(98))
				randmutb(M)
			else
				randmutg(M)
			domutcheck(M, null)
			M.UpdateAppearance()
	M.apply_effect(10 * removed, IRRADIATE, 0)
