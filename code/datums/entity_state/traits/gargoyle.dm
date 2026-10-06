/datum/trait_state/gargoyle
	var/energy = 100
	var/transformed = FALSE
	var/paused = FALSE
	EXPIRY_DECLARE(cooldown)

	var/obj/structure/gargoyle/statue	//another easy ref

	//Adjustable mod
	var/identifier = "statue"
	var/adjective = "hardens"
	var/material = "stone"
	var/tint = "#FFFFFF"

/datum/trait_state/gargoyle/setup()
	if (!ishuman(owner))
		return FALSE
	grant(owner, granted_verb(/mob/living/carbon/human/proc/gargoyle_transformation), src)
	grant(owner, granted_verb(/mob/living/carbon/human/proc/gargoyle_pause), src)
	grant(owner, granted_verb(/mob/living/carbon/human/proc/gargoyle_checkenergy), src)
	return TRUE

// detach(): the base drops every hook, including the Moved hook gargoyle_pause() adds.

/datum/trait_state/gargoyle/life_tick()
	if(QDELETED(gargoyle()))
		return
	if(transformed)
		if(!statue())
			transformed = FALSE
			return
		if(paused) //We somehow lost our energy while paused.
			unpause()
		statue().damage(-0.5)
		energy = min(energy+0.3, 100)

		//This is where we do all the 'make sure we don't die in statue form' stuff (unless you succumb or take MASSIVE damage.)
		//Bloodloss will still kill us, but if we are patient enough, we'll survive most other stuff.
		//If we had 150 brute (crit for most species) it'll take 3000 seconds (50 minutes) to heal back to full hp...So yes, while you can heal, it's not a good idea.
		if(gargoyle().is_injured())
			gargoyle().mend(TREAT_TISSUE_REPAIR, 0.1)
			gargoyle().mend(TREAT_BURN_CARE, 0.1)
			gargoyle().mend(TREAT_OXYGENATION, 1) //So you don't suffocate to death.
			gargoyle().mend(TREAT_ANTITOXIN, 0.1)
			gargoyle().mend(TREAT_GENETIC_REPAIR, 0.02) //yeah this is uber slow, no cheese allowed by combining it with bad genetics.
		return //Early return. If we're transformed, we can stop, we don't need to check anything else.
	if(energy > 0)
		if(!transformed && !paused)
			energy = max(0,energy-0.05)
	else if(!transformed && isturf(gargoyle().loc))
		gargoyle().gargoyle_transformation()

/datum/trait_state/gargoyle/proc/unpause()
	paused = FALSE
	unobserve(gargoyle(), /datum/notice/moved, src)
	return

/datum/trait_state/gargoyle/proc/on_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	unpause()

//verbs or action buttons...?
/mob/living/carbon/human/proc/gargoyle_transformation()
	set name = "Gargoyle - Petrification"
	set category = VERB_CAT_ABILITIES_GARGOYLE
	set desc = "Turn yourself into (or back from) being a gargoyle."
	var/datum/trait_state/gargoyle/G = get_trait_state(/datum/trait_state/gargoyle)
	G?.gargoyle_transformation()

/datum/trait_state/gargoyle/proc/gargoyle_transformation()
	if(gargoyle().stat == DEAD)
		return
	if(energy <= 0 && isturf(gargoyle().loc))
		to_chat(gargoyle(), span_danger("You suddenly turn into a [identifier] as you run out of energy!"))
	else if(!COOLDOWN_FINISHED(src, cooldown))
		var/time_to_wait = (cooldown - world.time) / (1 SECONDS)
		to_chat(gargoyle(), span_warning("You can't transform just yet again! Wait for another [round(time_to_wait,0.1)] seconds!"))
		return
	if(istype(gargoyle().loc, /obj/structure/gargoyle))
		spent(gargoyle().loc)
	else if(isturf(gargoyle().loc))
		new /obj/structure/gargoyle(gargoyle().loc, gargoyle())

/mob/living/carbon/human/proc/gargoyle_pause()
	set name = "Gargoyle - Pause"
	set category = VERB_CAT_ABILITIES_GARGOYLE
	set desc = "Pause your energy while standing still, so you don't use up any more, though you will lose a small amount upon moving again."
	var/datum/trait_state/gargoyle/G = get_trait_state(/datum/trait_state/gargoyle)
	G?.gargoyle_pause()

/datum/trait_state/gargoyle/proc/gargoyle_pause()
	if(gargoyle().stat)
		return

	if(!transformed && !paused)
		paused = TRUE
		observe(owner, /datum/notice/moved, src, then(PROC_REF(on_moved)))
		to_chat(owner, span_notice("You start conserving your energy."))

/mob/living/carbon/human/proc/gargoyle_checkenergy()
	set name = "Gargoyle - Check Energy"
	set category = VERB_CAT_ABILITIES_GARGOYLE
	set desc = "Check how much energy you have remaining as a gargoyle."
	var/datum/trait_state/gargoyle/G = get_trait_state(/datum/trait_state/gargoyle)
	G?.gargoyle_checkenergy()

/datum/trait_state/gargoyle/proc/gargoyle_checkenergy()
	to_chat(owner, span_notice("You have [round(energy,0.01)] energy remaining. It is currently [paused ? "stable" : (transformed ? "increasing" : "decreasing")]."))

/// Trait system: gargoyle energy.
/// One Life step per cycle while attached (doc/rewrite/om_retirement.md L1).
/datum/trait_state/gargoyle/life_steps()
	return list(seq_step(PROC_REF(life_tick), after = list(LIFE_INPUT, "life_type_pre"), key = "life_trait_gargoyle"))

/// LC-refs: the gargoyle mob (our owner).
/datum/trait_state/gargoyle/proc/gargoyle() as /mob/living/carbon/human
	return owner

/// The statue the gargoyle is standing as (a relation view).
/datum/trait_state/gargoyle/proc/statue() as /obj/structure/gargoyle
	return statue
