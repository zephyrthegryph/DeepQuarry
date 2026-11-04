/datum/reagent/drugs/talum_quem
	name = REAGENT_TALUMQUEM
	id = REAGENT_ID_TALUMQUEM
	description = " A very carefully tailored hallucinogen, for use of the Talum-Katish."
	taste_description = "bubblegum"
	taste_mult = 1.6
	color = "#db2ed8"
	high_message_list = list("The world distorts around you...!",
	"The walls look like they're moving...",
	"Nothing really makes sense right now.",
	"It feels like you've melded with the world around you...")
	sober_message_list = list("Everything feels... flat.", "You feel almost TOO grounded in your surroundings.")
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_ILLDRUG

/datum/reagent/drugs/talum_quem/affect_blood(mob/living/carbon/M, alien, removed)
	..()

	var/drug_strength = 29
	var/tox_strength = max(M.species.chem_strength_tox, 0) //Closer to 0 means they're more resistant to toxins. Higher than 1 means they're weaker to toxins.
	if(tox_strength > 0)
		drug_strength *= tox_strength
	// B21: everyone takes the toxin, scaled by their toxin strength (it used to hit only the immune).
	M.injure(INJURY_TOXIN, 10 * removed * tox_strength, source = src)

	M.status_at_least(STAT_DRUGGED, drug_strength)
	if(prob(10) && prob_proc == TRUE && isturf(M.loc) && !istype(M.loc, /turf/space) && M.canmove && !M.restrained())
		step(M, pick(GLOB.cardinal))
		prob_proc = FALSE
	if(prob(7) && prob_proc == TRUE)
		M.emote(pick("twitch", "drool", "moan", "giggle"))
		prob_proc = FALSE
