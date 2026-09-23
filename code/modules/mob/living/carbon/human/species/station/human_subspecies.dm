/datum/species/human/gravworlder
	name = "grav-adapted Human"
	name_plural = "grav-adapted Humans"
	blurb = "Heavier and stronger than a baseline human, gravity-adapted people have \
	thick radiation-resistant skin with a high lead content, denser bones, and recessed \
	eyes beneath a prominent brow in order to shield them from the glare of a dangerously \
	bright, alien sun. This comes at the cost of mobility, flexibility, and increased \
	oxygen requirements to support their robust metabolism."
	icobase = 'icons/mob/human_races/subspecies/r_gravworlder.dmi'

	flash_mod =     0.9
	radiation_mod = 0.5
	factor_baseline = alist(BF_SLOWDOWN = 1, BF_INCOMING_PHYSICAL = 0.85, BF_DEMAND = 1.1)

/datum/species/human/spacer
	name = "space-adapted Human"
	name_plural = "space-adapted Humans"
	blurb = "Lithe and frail, these sickly folk were engineered for work in environments that \
	lack both light and atmosphere. As such, they're quite resistant to asphyxiation as well as \
	toxins, but they suffer from weakened bone structure and a marked vulnerability to bright lights."
	icobase = 'icons/mob/human_races/subspecies/r_spacer.dmi'

	factor_baseline = alist(BF_INCOMING_PHYSICAL = 1.1, BF_INCOMING_THERMAL = 1.1, BF_INCOMING_TOXIC = 0.9, BF_DEMAND = 0.8)
	flash_mod = 1.2

/datum/species/human/vatgrown
	name = SPECIES_HUMAN_VATBORN
	name_plural = "Vatborn"
	blurb = "With cloning on the forefront of human scientific advancement, cheap mass production \
	of bodies is a very real and rather ethically grey industry. Vat-grown or Vatborn humans tend to be \
	paler than baseline, with no appendix and fewer inherited genetic disabilities, but a more aggressive metabolism."
	icobase = 'icons/mob/human_races/subspecies/r_vatgrown.dmi'

	factor_baseline = alist(BF_METABOLISM = 1.15, BF_INCOMING_TOXIC = 1.1)
	has_organ = list(
		O_HEART =    /obj/item/organ/internal/heart,
		O_LUNGS =    /obj/item/organ/internal/lungs,
		O_VOICE =    /obj/item/organ/internal/voicebox,
		O_LIVER =    /obj/item/organ/internal/liver,
		O_KIDNEYS =  /obj/item/organ/internal/kidneys,
		O_SPLEEN =   /obj/item/organ/internal/spleen/minor,
		O_BRAIN =    /obj/item/organ/internal/brain,
		O_EYES =     /obj/item/organ/internal/eyes,
		O_STOMACH =	 /obj/item/organ/internal/stomach,
		O_INTESTINE =/obj/item/organ/internal/intestine
		)

/*
// These guys are going to need full resprites of all the suits/etc so I'm going to
// define them and commit the sprites, but leave the clothing for another day.
/datum/species/human/chimpanzee
	name = "uplifted Chimpanzee"
	name_plural = "uplifted Chimpanzees"
	blurb = "Ook ook."
	icobase = 'icons/mob/human_races/subspecies/r_upliftedchimp.dmi'
*/
