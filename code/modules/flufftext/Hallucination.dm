/*
Ideas for the subtle effects of hallucination:

Light up oxygen/phoron indicators (done)
Cause health to look critical/dead, even when standing (done)
Characters silently watching you
Brief flashes of fire/space/bombs/c4/dangerous shit (done)
Items that are rare/traitorous/don't exist appearing in your inventory slots (done)
Strange audio (should be rare) (done)
Gunshots/explosions/opening doors/less rare audio (done)
*/

/// Active hallucinations on a carbon. Owned by the
/// mob's `hallucinations` var; one at a time, first come first serve.
/datum/hallucinations
	VAR_PRIVATE/mob/living/carbon/human/our_human = null
	/// The flash-of-danger image this event made and owns; nulled when it is deleted.
	VAR_PRIVATE/image/client_only/halimage
	/// The body/food image this event made and owns; nulled when it is deleted.
	VAR_PRIVATE/image/client_only/halbody
	/// The fake item this event put on the client's screen (owned: deleted with the event).
	VAR_PRIVATE/obj/halitem
	/// The client whose screen shows halitem: a relation view.
	VAR_PRIVATE/client/halitem_client

	VAR_PRIVATE/hal_crit = FALSE
	VAR_PRIVATE/hal_screwyhud = HUD_HALLUCINATION_NONE

CAPABILITIES(/datum/hallucinations)
	owns_one(nameof(halitem), /obj)

/mob/living/carbon/var/datum/hallucinations/hallucinations

/datum/hallucinations/New(mob/living/carbon/human/H)
	..()
	rel_set(src, nameof(our_human), H)
	make_timer()

// a held hallucination item is removed.
/datum/hallucinations/on_destroy(force)
	if(halitem)
		remove_hallucination_item()
	// Images are not datums: deleting one takes it off every client.images and nulls these vars.
	if(halbody)
		ended_with(halbody, src)
	if(halimage)
		ended_with(halimage, src)
	..()

/datum/hallucinations/proc/make_timer()
	PROTECTED_PROC(TRUE)
	// Sooner the stronger the hallucination: 20-50 s at 25 points, a quarter of that at 100.
	var/delay = (rand(20, 50) SECONDS) / (min(our_human.status_units(STAT_HALLUCINATING), 100) / 25)
	after(src, delay, PROC_REF(trigger))

/datum/hallucinations/proc/get_fakecrit()
	SHOULD_NOT_OVERRIDE(TRUE)
	return hal_crit

/datum/hallucinations/proc/get_hud_state()
	SHOULD_NOT_OVERRIDE(TRUE)
	return hal_screwyhud

/////////////////////////////////////////////////////////////////////////////////////////////////////
// Traditional hallucinations
/////////////////////////////////////////////////////////////////////////////////////////////////////
/mob/living/carbon/proc/handle_hallucinations()
	if(get_hallucination_state() || !client || has_trait(src, TRAIT_MADNESS_IMMUNE))
		return
	start_hallucinations(/datum/hallucinations)

/// Starts a hallucination run of `hallucination_type` unless one is already running. Humans only.
/mob/living/carbon/proc/start_hallucinations(hallucination_type = /datum/hallucinations)
	if(hallucinations || !ishuman(src))
		return hallucinations
	rel_set(src, nameof(hallucinations), new hallucination_type(src))
	return hallucinations

/mob/living/carbon/proc/get_hallucination_state()
	RETURN_TYPE(/datum/hallucinations)
	return hallucinations

/datum/hallucinations/proc/trigger()
	PROTECTED_PROC(TRUE)
	if(QDELETED(our_human))
		ended_with(src, our_human)
		return
	if(!our_human.client)
		spent(src)
		return
	if(our_human.status_units(STAT_HALLUCINATING) < HALLUCINATION_THRESHOLD)
		spent(src)
		return
	handle_hallucinating()
	make_timer()

/datum/hallucinations/proc/handle_hallucinating()
	PROTECTED_PROC(TRUE)
	var/halpick = rand(1,100)
	switch(halpick)
		if(0 to 15)
			event_hudscrew()
		if(16 to 25)
			event_fake_item()
		if(26 to 40)
			event_flash_environmental_threats()
		if(41 to 65)
			event_strange_sound()
		if(66 to 70)
			if(prob(20) && our_human.nutrition < 100)
				event_hunger() // Hungi, meant for xenochi but this is too funny to pass up
			else
				event_flash_monsters()
		if(71 to 72)
			event_sleeping()
		if(73 to 75) // If you don't want hallucination beatdowns, comment this out
			event_attacker()
		if(76 to 80)
			event_painmessage()

/////////////////////////////////////////////////////////////////////////////////////////////////////
// Xenochimera hallucinations
// Unlike normal hallucinations this one is triggered from handle_feral randomly.
// So it destroys itself after it triggers, freeing up space for the next run of it.
/////////////////////////////////////////////////////////////////////////////////////////////////////
/datum/hallucinations/xenochimera/make_timer()
	var/datum/xenochimera/XC = our_human.xenochimera
	var/F = XC ? (XC.feral / 10) : 1
	after(src, ((rand(20,50) SECONDS) / F), PROC_REF(trigger))

/datum/hallucinations/xenochimera/trigger()
	if(QDELETED(our_human))
		ended_with(src, our_human)
		return
	if(!our_human.client)
		spent(src)
		return
	var/datum/xenochimera/XC = our_human.xenochimera
	if(!XC || XC.feral < XENOCHIFERAL_THRESHOLD)
		spent(src)
		return
	handle_hallucinating()
	expire(rand(3,9)SECONDS)

/datum/hallucinations/xenochimera/handle_hallucinating()
	var/halpick = rand(1,100)
	switch(halpick)
		if(0 to 15) //15% chance
			//Screwy HUD
			event_hudscrew()
		if(16 to 25) //10% chance
			event_fake_item()
		if(26 to 35) //10% chance
			event_flash_environmental_threats()
		if(36 to 55) //20% chance
			event_strange_sound()
		if(56 to 60) //5% chance
			event_flash_monsters()
		if(61 to 85) //25% chance
			event_hunger()
		if(86 to 100) //15% chance
			event_hear_voices()
