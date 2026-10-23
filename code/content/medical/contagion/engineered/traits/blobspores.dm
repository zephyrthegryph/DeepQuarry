/*
//////////////////////////////////////
Blob Spores

	Slightly hidden
	Major Increases to resistance.
	Reduces stage speed.
	Slight boost to transmission
	Admin Level.

BONUS
	The host coughs up blob spores

//////////////////////////////////////
*/
/datum/viral_trait/blobspores
	name = "Blob Spores"
	desc = "This symptom causes the host to produce blob spores, which will leave the host at the later stages, and if the host dies, all of the spores will erupt from the host at the same time, while also producing a blob tile."
	stealth = 1
	resistance = 6
	stage_speed = -2
	transmission = 1
	level = 9
	threat = 3
	naturally_occuring = FALSE
	symptom_delay_min = 20 SECONDS
	symptom_delay_max = 40 SECONDS

	threshold_descs = list(
		"Resistance 8" = "Spawns a strong blob instead of a normal blob",
		"Resistance 11" = "There is a chance to spawn a factory blob, instead of a normal blob.",
		"Resistance 14" = "Has a chance to spawn a blob node instead of a normal blob"
	)

	var/ready_to_pop
	var/factory_blob
	var/strong_blob
	var/node_blob

	prefixes = list("Xeno", "Sporing ")
	bodies = list("Blob")

/datum/viral_trait/blobspores/severityset(datum/affliction/contagion/engineered/A)
	. = ..()
	if(A.resistance >= 14)
		threat += 1

/datum/viral_trait/blobspores/Start(datum/affliction/contagion/engineered/A)
	if(!..())
		return

	if(A.resistance >= 11)
		factory_blob = TRUE
	if(A.resistance >= 8)
		strong_blob = TRUE
		if(A.resistance >= 14)
			node_blob = TRUE

/datum/viral_trait/blobspores/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	var/mob/living/M = A.host

	switch(A.stage)
		if(1)
			to_chat(M, span_notice("You feel bloated."))

			if(!M.has_status(STAT_JITTERY))
				to_chat(M, span_notice("You feel a bit jittery."))
				M.status_adjust(STAT_JITTERY, 100 + rand(12,16))

		if(2)
			if(ishuman(M))
				var/mob/living/carbon/human/H = M
				H.vomit(TRUE, FALSE)
		if(3, 4)
			to_chat(M, span_notice("You feel blobby?"))

		if(5)
			M.audible_emote("coughs up a small amount of blood!")
			if(ishuman(M))
				var/mob/living/carbon/human/H = M
				var/bleeding_rng = rand(1, 2)
				H.drip(bleeding_rng)

/datum/viral_trait/blobspores/OnStageChange(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(A.stage == 5)
		ready_to_pop = TRUE

/datum/viral_trait/blobspores/OnDeath(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(!ready_to_pop)
		return
	var/mob/living/M = A.host
	act_message(M, null, others = span_danger("%U% starts swelling grotesquely!"))
	after(src, 10 SECONDS, PROC_REF(pop), with = list(A, M))

/datum/viral_trait/blobspores/proc/pop(datum/affliction/contagion/engineered/A, mob/living/M)
	if(!A || !M)
		return
	var/list/blob_options = list(/obj/structure/blob/normal)
	if(factory_blob)
		blob_options += /obj/structure/blob/factory
	if(strong_blob)
		blob_options += /obj/structure/blob/shield
	if(node_blob)
		blob_options += /obj/structure/blob/node
	var/pick_blob = pick(blob_options)
	for(var/i in 1 to rand(1, 6))
		new /mob/living/simple_mob/blob/spore(M.loc)
	new pick_blob(M.loc)

	act_message(M, null, others = span_danger("A huge mass of blob and blob spores burst out of %U%!"))
