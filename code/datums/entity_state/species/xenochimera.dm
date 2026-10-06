/// Xenochimera species state (feralness, regeneration). An owned plain datum held in
/// /mob/living/carbon/human/var/xenochimera; formerly a component.
/datum/xenochimera
	VAR_PRIVATE/laststress = 0
	VAR_PRIVATE/mob/living/carbon/human/owner
	var/feral = 0
	var/revive_ready = REVIVING_READY
	/// Time before another regeneration may start.
	COOLDOWN_DECLARE(revive_cooldown)
	EXPIRY_DECLARE(revive_finished)
	VAR_PRIVATE/regen_sounds = SFX_EFFECTS_MOB_EFFECTS_XENOCHIMERA_REGEN_MIX
	VAR_PRIVATE/datum/transhuman/body_record/revival_record

CAPABILITIES(/datum/xenochimera)
	owns_one(nameof(revival_record), /datum/transhuman/body_record)

/datum/xenochimera/New(mob/living/carbon/human/new_owner)
	..()
	if(!ishuman(new_owner))
		log_runtime("XENOCHIMERA: /datum/xenochimera created for non-human [new_owner] ([new_owner?.type]); ignoring.")
		return
	rel_set(src, nameof(owner), new_owner) // one-sided back view: the mob owns us in xenochimera
	observe(owner, /datum/notice/human_dna_finalized, src, then(PROC_REF(on_dna_finalized)))
	if(owner.dna)
		handle_record()
	grant(owner, granted_verb(/mob/living/carbon/human/proc/reconstitute_form), src)

/mob/living/carbon/human/var/datum/xenochimera/xenochimera

// the owner loses the reconstitute verb and its pointer to us.
/datum/xenochimera/lifecycle_prerelease()
	..()
	if(owner)
		revoke(owner, granted_verb(/mob/living/carbon/human/proc/reconstitute_form), src)

/datum/xenochimera/proc/on_dna_finalized(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	handle_record()

/datum/xenochimera/proc/handle_record()
	if(QDELETED(owner))
		return
	rel_set(src, nameof(revival_record), new /datum/transhuman/body_record(owner))

/// Ticked from the human species_components life stage.
/datum/xenochimera/proc/handle_comp()
	if(QDELETED(owner))
		return
	handle_feralness()
	handle_regeneration()

/datum/xenochimera/proc/handle_regeneration()
	if(revive_ready == REVIVING_NOW || revive_ready == REVIVING_DONE)
		owner.status_set(EFFECT_STUNNED, 5)
		owner.canmove = 0
		owner.set_does_not_breathe(TRUE)
		if(prob(2)) // 2% chance of playing squelchy noise while reviving, which is run roughly every 2 seconds/tick while regenerating.
			playsound(owner, regen_sounds, 30)
			owner.visible_message(span_danger("<p>" + span_huge("[owner.name]'s motionless form shudders grotesquely, rippling unnaturally.") + "</p>"))
		if(!owner.lying)
			owner.lay_down()

/datum/xenochimera/proc/set_revival_delay(time)
	revive_ready = REVIVING_NOW
	EXPIRY_SET(src, revive_finished, time SECONDS, CLOCK_WORLD) // When do we finish reviving? Allows us to find out when we're done, called by the alert currently.

/datum/xenochimera/proc/trigger_revival(from_save_slot)
	ASSERT(revival_record)
	if(HAS_SYNTHETIC_BIOLOGY(owner))
		revival_record.revive_xenochimera(owner,TRUE,from_save_slot)
	else
		revival_record.revive_xenochimera(owner,FALSE,from_save_slot)
	if(from_save_slot)
		handle_record() // Update record

/datum/xenochimera/proc/handle_feralness()
	//first, calculate how stressed the chimera is

	//Low-ish nutrition has messages and can eventually cause feralness
	var/hunger = max(0, 150 - owner.nutrition)

	//pain makes feralness a thing
	var/shock = 0.75*owner.traumatic_shock

	//Caffeinated or otherwise overexcited xenochimera can become feral and have special messages
	var/jittery = max(0, owner.status_units(EFFECT_JITTERY) - 100)

	//Are we in danger of ferality?
	var/danger = FALSE
	var/feral_state = FALSE

	//finally, calculate the current stress total the chimera is operating under, and the cause
	var/currentstress = (hunger + shock + jittery)
	var/cause = "stress"
	if(hunger > shock && hunger > jittery)
		cause = "hunger"
	else if (shock > hunger && shock > jittery)
		cause = "shock"
	else if (jittery > shock && jittery > hunger)
		cause = "jittery"

	//check to see if they go feral if they weren't before
	if(!feral && !isbelly(owner.loc))
		// if stress is below 15, no chance of snapping. Also if they weren't feral before, they won't suddenly become feral unless they get MORE stressed
		if((currentstress > laststress) && prob(clamp(currentstress-15, 0, 100)) )
			go_feral(currentstress, cause)
			feral = currentstress //update the local var

		//they didn't go feral, give 'em a chance of hunger messages
		else if(owner.nutrition <= 200 && prob(0.5))
			switch(owner.nutrition)
				if(150 to 200)
					to_chat(owner,span_info("You feel rather hungry. It might be a good idea to find some some food..."))
				if(100 to 150)
					to_chat(owner,span_warning("You feel like you're going to snap and give in to your hunger soon... It would be for the best to find some [pick("food","prey")] to eat..."))
					danger = TRUE

	//now the check's done, update their brain so it remembers how stressed they were
	if(!isbelly(owner.loc)) //another sanity check for brain implant shenanigans, also no you don't get to hide in a belly and get your laststress set to a huge amount to skip rolls
		laststress = currentstress

	// Handle being feral
	if(feral)
		//We're feral
		feral_state = TRUE

		//If they're still stressed, they stay feral
		if(currentstress >= 15)
			danger = TRUE
			feral = max(feral, currentstress)

		else
			feral = max(0,--feral)

			// Being in a belly or in the darkness decreases stress further. Helps mechanically reward players for staying in darkness + RP'ing appropriately. :9
			var/turf/T = get_turf(owner)
			if(feral && (isbelly(owner.loc) || T.get_lumcount() <= 0.1))
				feral = max(0,--feral)

		//Did we just finish being feral?
		if(!feral)
			feral_state = FALSE
			to_chat(owner,span_info("Your thoughts start clearing, your feral urges having passed - for the time being, at least."))
			log_and_message_admins("is no longer feral.", owner)
			update_xenochimera_hud(danger, feral_state)
			return

		//If they lose enough health to hit softcrit, the shock life system will keep resetting this. Otherwise, pissed off critters will lose shock faster than they gain it.
		owner.adjust_shock(-(feral/20), "feral")

		//Handle light/dark areas
		var/turf/T = get_turf(owner)
		if(!T)
			update_xenochimera_hud(danger, feral_state)
			return //Nullspace
		var/darkish = T.get_lumcount() <= 0.1

		//Don't bother doing heavy lifting if we weren't going to give emotes anyway.
		if(!prob(1))

			//This is basically the 'lite' version of the below block.
			var/list/nearby = owner.living_mobs(world.view)

			//Not in the dark, or a belly, and out in the open.
			if(!darkish && isturf(owner.loc) && !isbelly(owner.loc)) // Added specific check for if in belly

				//Always handle feral if nobody's around and not in the dark.
				if(!nearby.len)
					handle_feral()

				//Rarely handle feral if someone is around
				else if(prob(1))
					handle_feral()

			//And bail
			update_xenochimera_hud(danger, feral_state)
			return

		// In the darkness, or "hidden", or in a belly. No need for custom scene-protection checks as it's just an occational infomessage.
		if(darkish || !isturf(owner.loc) || isbelly(owner.loc)) // Specific check for if in belly. !isturf should do this, but JUST in case.
			// If hurt, tell 'em to heal up
			if (cause == "shock")
				to_chat(owner,span_info("This place seems safe, secure, hidden, a place to lick your wounds and recover..."))

			//If hungry, nag them to go and find someone or something to eat.
			else if(cause == "hunger")
				to_chat(owner,span_info("Secure in your hiding place, your hunger still gnaws at you. You need to catch some food..."))

			//If jittery, etc
			else if(cause == "jittery")
				to_chat(owner,span_info("sneakysneakyyesyesyescleverhidingfindthingsyessssss"))

			//Otherwise, just tell them to keep hiding.
			else
				to_chat(owner,span_info("...safe..."))

		// NOT in the darkness
		else

			//Twitch twitch
			if(!owner.stat)
				owner.emote("twitch")

			var/list/nearby = owner.living_mobs(world.view)

			// Someone/something nearby
			if(nearby.len)
				var/M = pick(nearby)
				if(cause == "shock")
					to_chat(owner,span_danger("You're hurt, in danger, exposed, and [M] looks to be a little too close for comfort..."))
				else
					to_chat(owner,span_danger("Every movement, every flick, every sight and sound has your full attention, your hunting instincts on high alert... In fact, [M] looks extremely appetizing..."))

			// Nobody around
			else
				if(cause == "hunger")
					to_chat(owner,span_danger("Confusing sights and sounds and smells surround you - scary and disorienting it may be, but the drive to hunt, to feed, to survive, compels you."))
				else if(cause == "jittery")
					to_chat(owner,span_danger("yesyesyesyesyesyesgetthethingGETTHETHINGfindfoodsfindpreypounceyesyesyes"))
				else
					to_chat(owner,span_danger("Confusing sights and sounds and smells surround you, this place is wrong, confusing, frightening. You need to hide, go to ground..."))

	// HUD update time
	update_xenochimera_hud(danger, feral_state)

/datum/xenochimera/proc/update_xenochimera_hud(danger, feral)
	if(owner.xenochimera_danger_display)
		owner.xenochimera_danger_display.invisibility = INVISIBILITY_NONE
		if(danger && feral)
			owner.xenochimera_danger_display.icon_state = "danger11"
		else if(danger && !feral)
			owner.xenochimera_danger_display.icon_state = "danger10"
		else if(!danger && feral)
			owner.xenochimera_danger_display.icon_state = "danger01"
		else
			owner.xenochimera_danger_display.icon_state = "danger00"

	return

/datum/xenochimera/proc/go_feral(stress, cause)
	// Going feral due to hunger
	if(cause == "hunger")
		to_chat(owner,span_danger(span_large("Something in your mind flips, your instincts taking over, no longer able to fully comprehend your surroundings as survival becomes your primary concern - you must feed, survive, there is nothing else. Hunt. Eat. Hide. Repeat.")))
		log_and_message_admins("has gone feral due to hunger.", owner)

	// If they're hurt, chance of snapping.
	else if(cause == "shock")
		//If the majority of their shock is due to raw pain, give them a different message (3x multiplier on check as pain is 2x - meaning t_s must be at least 3x for other damage sources to be the greater part)
		if(3*owner.current_pain() >= owner.traumatic_shock)
			to_chat(owner,span_danger(span_large("The pain! It stings! Got to get away! Your instincts take over, urging you to flee, to hide, to go to ground, get away from here...")))
			log_and_message_admins("has gone feral due to pain.", owner)

		//Majority due to other damage sources
		else
			to_chat(owner,span_danger(span_large("Your fight-or-flight response kicks in, your injuries too much to simply ignore - you need to flee, to hide, survive at all costs - or destroy whatever is threatening you.")))
			log_and_message_admins("has gone feral due to injury.", owner)

	//No hungry or shock, but jittery
	else if(cause == "jittery")
		to_chat(owner,span_warning(span_large("Suddenly, something flips - everything that moves is... potential prey. A plaything. This is great! Time to hunt!")))
		log_and_message_admins("has gone feral due to jitteriness.", owner)

	else // catch-all just in case something weird happens
		to_chat(owner,span_warning(span_large("The stress of your situation is too much for you, and your survival instincts kick in!")))
		log_and_message_admins("has gone feral for unknown reasons.", owner)
	//finally, set their feral var
	feral = stress
	if(!owner.stat)
		owner.emote("twitch")

/datum/xenochimera/proc/handle_feral()
	if(QDELETED(owner) || owner.get_hallucination_state() || !owner.client || feral < XENOCHIFERAL_THRESHOLD)
		return
	owner.start_hallucinations(/datum/hallucinations/xenochimera)

/atom/movable/screen/xenochimera
	icon = 'icons/mob/chimerahud.dmi'
	invisibility = INVISIBILITY_ABSTRACT

/atom/movable/screen/xenochimera/danger_level
	name = "danger level"
	icon_state = "danger00"		//first number is bool of whether or not we're in danger, second is whether or not we're feral
	alpha = 200

/mob/living/carbon/human/proc/reconstitute_form() //Scree's race ability.in exchange for: No cloning.
	set name = "Reconstitute Form"
	set category = VERB_CAT_ABILITIES_XENOCHIMERA
	return reconstitute_form_stage(list())

/mob/living/carbon/human/proc/reconstitute_form_stage(list/answers)
	var/datum/xenochimera/xc = get_xenochimera_state()
	if(!xc)
		return
	if(is_incorporeal())
		to_chat(src, "You cannot regenerate while incorporeal.")
		return
	// Sanity is mostly handled in chimera_regenerate()
	if(stat == DEAD)
		var/confirm = answers["a1"]
		if(!("a1" in answers))
			open_request(src, /datum/prompt/choice/xenochimera_review, PROC_REF(reconstitute_form_answered), answerer = src, answers = answers, answer_key = "a1", question = "Are you sure you want to regenerate your corpse? This process can take up to thirty minutes. Additionally, you may regenerate your appearance based on your current form or the appearance of the currently loaded slot.", title = "Confirm Regeneration", choices = list("Yes", "No"))
			return
		if(isnull(confirm))
			return
		if(confirm == "Yes")
			xc.chimera_regenerate()
	else if(quickcheckuninjured())
		var/confirm = answers["a2"]
		if(!("a2" in answers))
			open_request(src, /datum/prompt/choice/xenochimera_review, PROC_REF(reconstitute_form_answered), answerer = src, answers = answers, answer_key = "a2", question = "Are you sure you want to regenerate? As you are uninjured this will only take 30 seconds. Additionally, you may regenerate your appearance based on your current form or the appearance of the currently loaded slot.", title = "Confirm Regeneration", choices = list("Yes", "No"))
			return
		if(isnull(confirm))
			return
		if(confirm == "Yes")
			xc.chimera_regenerate()
	else
		var/confirm = answers["a3"]
		if(!("a3" in answers))
			open_request(src, /datum/prompt/choice/xenochimera_review, PROC_REF(reconstitute_form_answered), answerer = src, answers = answers, answer_key = "a3", question = "Are you sure you want to completely reconstruct your form? This process can take up to fifteen minutes, depending on how hungry you are, and you will be unable to move. Additionally, you may regenerate your appearance based on your current form or the appearance of the currently loaded slot", title = "Confirm Regeneration", choices = list("Yes", "No"))
			return
		if(isnull(confirm))
			return
		if(confirm == "Yes")
			xc.chimera_regenerate()

/datum/xenochimera/proc/chimera_regenerate()
	if(!owner)
		return
	//If they're already regenerating
	switch(revive_ready)
		if(REVIVING_NOW)
			to_chat(owner, "You are already reconstructing, just wait for the reconstruction to finish!")
			return
		if(REVIVING_DONE)
			to_chat(owner, "Your reconstruction is done, but you need to hatch now.")
			return
	if(!COOLDOWN_FINISHED(src, revive_cooldown))
		to_chat(owner, "You can't use that ability again so soon!")
		return

	var/time = min(900, (120+780/(1 + owner.nutrition/100))) //capped at 15 mins, roughly 6 minutes at 250 (yellow) nutrition, 4.1 minutes at 500 (grey), cannot be below 2 mins
	if (owner.quickcheckuninjured()) //if you're completely uninjured, then you get a speedymode - check health first for quickness
		time = 30

	//Clicked regen while dead.
	if(owner.stat == DEAD)

		//reviving from dead takes extra nutriment to be provided from outside OR takes twice as long and consumes extra at the end
		if(!owner.hasnutriment())
			time = time*2

		to_chat(owner, "You begin to reconstruct your form. You will not be able to move during this time. It should take aproximately [round(time)] seconds.")

		//Scary spawnerization.
		set_revival_delay(time)
		owner.throw_alert("regen", /atom/movable/screen/alert/xenochimera/reconstitution)
		after(src, time SECONDS, PROC_REF(chimera_regenerate_ready))

	//Clicked regen while NOT dead
	else
		to_chat(owner, "You begin to reconstruct your form. You will not be able to move during this time. It should take aproximately [round(time)] seconds.")

		//Waiting for regen after being alive
		set_revival_delay(time)
		owner.throw_alert("regen", /atom/movable/screen/alert/xenochimera/reconstitution)
		after(src, time SECONDS, PROC_REF(chimera_regenerate_nutrition))
	owner.lying = TRUE

/datum/xenochimera/proc/chimera_regenerate_nutrition()
	if(!owner)
		return
	//Slightly different flavour messages
	if(owner.stat != DEAD || owner.hasnutriment())
		to_chat(owner, span_notice("Consciousness begins to stir as your new body awakens, ready to hatch.."))
	else
		to_chat(owner, span_warning("Consciousness begins to stir as your battered body struggles to recover from its ordeal.."))
	grant(owner, granted_verb(/mob/living/carbon/human/proc/hatch), src)
	revive_ready = REVIVING_DONE
	owner << sound('sound/effects/mob_effects/xenochimera/hatch_notification.ogg',0,0,0,30)
	owner.clear_alert("regen")
	owner.throw_alert("hatch", /atom/movable/screen/alert/xenochimera/readytohatch)

/datum/xenochimera/proc/chimera_regenerate_ready()
	if(!owner)
		return
	// check to see if they've been fixed by outside forces in the meantime such as defibbing
	if(owner.stat != DEAD)
		to_chat(owner, span_notice("Your body has recovered from its ordeal, ready to regenerate itself again."))
		revive_ready = REVIVING_READY
		COOLDOWN_RESET(src, revive_cooldown) //reset their cooldown
		owner.clear_alert("regen")
		owner.throw_alert("hatch", /atom/movable/screen/alert/xenochimera/readytohatch)

	// Was dead, still dead.
	else
		to_chat(owner, span_notice("Consciousness begins to stir as your new body awakens, ready to hatch."))
		grant(owner, granted_verb(/mob/living/carbon/human/proc/hatch), src)
		revive_ready = REVIVING_DONE
		owner << sound('sound/effects/mob_effects/xenochimera/hatch_notification.ogg',0,0,0,30)
		owner.clear_alert("regen")
		owner.throw_alert("hatch", /atom/movable/screen/alert/xenochimera/readytohatch)

/mob/living/carbon/human/proc/hatch()
	set name = "Hatch"
	set category = VERB_CAT_ABILITIES_XENOCHIMERA
	return hatch_stage(list())

/mob/living/carbon/human/proc/hatch_stage(list/answers)
	var/datum/xenochimera/xc = get_xenochimera_state()
	if(!xc)
		return
	if(xc.revive_ready != REVIVING_DONE)
		return //Hwhat?

	// Default is use internal record, even if closes menu
	var/reload_slot = answers["a4"]
	if(!("a4" in answers))
		open_request(src, /datum/prompt/choice/xenochimera_review, PROC_REF(hatch_answered), answerer = src, answers = answers, answer_key = "a4", question = "Regenerate from your current form, or from the appearance of your current character slot(This will not change your current species or traits.)", title = "Regenerate Form", choices = list("Current Form", "From Slot"), cancel_default = "Current Form")
		return
	if(isnull(reload_slot))
		return

	// Check if valid to load from this slot
	var/from_slot = ""
	from_slot = "You'll hatch using your current appearance"
	if(reload_slot == "From Slot" && client)
		if(client.prefs.read_preference(/datum/preference/choiced/species) == SPECIES_PROTEAN) // Exploit protection
			to_chat(src,span_warning("You cannot copy nanoform prosthetic limbs from this species. Please try another character."))
			return
		var/list/organ_data = client.prefs.read_preference(/datum/preference/organ_data)
		var/slot_is_synth = (organ_data && (O_BRAIN in organ_data) && organ_data[O_BRAIN])
		if(slot_is_synth && !HAS_SYNTHETIC_BIOLOGY(src)) // Prevents some pretty weird situations
			to_chat(src,span_warning("Cannot apply character appearance. [slot_is_synth ? "The slot's character is synthetic." : "The slot's character is organic."] Slot must match the current body's synthetic state. Please try another character."))
			return
		from_slot = "You'll hatch using [client.prefs.read_preference(/datum/preference/name/real_name)]'s appearance"

	var/confirm = answers["a5"]
	if(!("a5" in answers))
		open_request(src, /datum/prompt/choice/xenochimera_review, PROC_REF(hatch_answered), answerer = src, answers = answers, answer_key = "a5", question = "Are you sure you want to hatch right now? This will be very obvious to anyone in view. [from_slot]! Are you sure?", title = "Confirm Regeneration", choices = list("Yes", "No"))
		return
	if(isnull(confirm))
		return
	if(confirm == "Yes")

		///This makes xenochimera shoot out their robotic limbs if they're not a FBP.
		if(!HAS_SYNTHETIC_BIOLOGY(src)) //If we aren't repairing robotic limbs (FBP) we reject any robot limbs we have and kick them out!
			for(var/O in organs_by_name)
				var/obj/item/organ/external/organ = organs_by_name[O]
				if(!istype(organ, /obj/item/organ/external))
					continue
				if(!organ.robotic)
					continue
				else
					organ.removed()
		///End of xenochimera limb rejection code.

		//Dead when hatching
		// var/sickness_duration = 10 MINUTES //
		var/has_braindamage = FALSE
		if(stat == DEAD)
			//Reviving from ded takes extra nutrition - if it isn't provided from outside sources, it comes from you
			if(!hasnutriment())
				set_nutrition(nutrition * 0.75)
				// sickness_duration = 20 MINUTES //
			has_braindamage = TRUE

		// Finalize!
		revoke(src, granted_verb(/mob/living/carbon/human/proc/hatch), xc)
		clear_alert("hatch")
		xc.chimera_hatch((reload_slot == "From Slot" && client))
		act_message(src, null, others = span_warning(span_huge("%U% rises to %THEIR% feet."))) //Bloody hell...
		if(has_braindamage)
			// apply_body_effect(/datum/body_effect/resleeving_sickness/chimera, sickness_duration) //
			injure(INJURY_NEURAL, 5) // if they're reviving from dead, they come back with 5 brain damage on top of whatever's unhealed.

/datum/xenochimera/proc/chimera_hatch(from_save_slot)
	if(!owner)
		return

	revoke(owner, granted_verb(/mob/living/carbon/human/proc/hatch), src)
	to_chat(owner, span_notice("Your new body awakens, bursting free from your old skin."))
	//Modify and record values (half nutrition and braindamage)
	var/old_nutrition = owner.nutrition
	var/braindamage = min(5, max(0, (owner.injury_load(INJURY_CATEGORY_NEURAL)-1) * 0.5)) //brain damage is tricky to heal and might take a couple of goes to get rid of completely.
	var/uninjured=owner.quickcheckuninjured()
	trigger_revival(from_save_slot)

	owner.remove_mutation(HUSK)
	owner.injure(INJURY_NEURAL, braindamage, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	owner.species.update_vore_belly_def_variant()

	if(!uninjured)
		owner.set_nutrition(old_nutrition * 0.5)
		//Drop everything
		for(var/obj/item/W in owner)
			owner.drop_from_inventory(W)
		//Visual effects
		var/T = get_turf(owner)
		var/blood_color = owner.species.blood_color
		var/flesh_color = owner.species.flesh_color
		gibs(T, null, /obj/effect/gibspawner/human/xenochimera, flesh_color, blood_color)
		owner.visible_message(span_danger(span_huge("The lifeless husk of [owner] bursts open, revealing a new, intact copy in the pool of viscera."))) //Bloody hell...
		play_sfx(T, SFX_EFFECTS_MOB_EFFECTS_XENOCHIMERA_HATCH)
	else //lower cost for doing a quick cosmetic revive
		owner.set_nutrition(old_nutrition * 0.9)

	//Unfreeze some things
	owner.set_does_not_breathe(FALSE)
	owner.update_canmove()
	owner.status_adjust(EFFECT_STUNNED, 2)

	revive_ready = REVIVING_READY
	COOLDOWN_START(src, revive_cooldown, 10 MINUTES) //set the cooldown, Reduced this to 10 minutes, you're playing with fire if you're reviving that often.

/datum/body_effect/resleeving_sickness/chimera //near identical to the regular version, just with different flavortexts
	stacks = MODIFIER_STACK_FORBID
	name = "imperfect regeneration"
	desc = "You feel rather weak and unfocused, having just regrown your body not so long ago."

	on_created_text = span_warning(span_large("You feel weak and unsteady, that regeneration having been rougher than most."))
	on_expired_text = span_notice(span_large("You feel your strength and focus return to you."))

/obj/effect/gibspawner/human/xenochimera
	fleshcolor = "#14AD8B"
	bloodcolor = "#14AD8B"

///This is bad and should not be done this way, but xenochimera was hardcoded in SO many places that it's going to be a hassle to completely undo.
/mob/proc/get_feralness()
	var/datum/xenochimera/xc = get_xenochimera_state()
	if(xc)
		return xc.feral

/mob/proc/get_xenochimera_state()
	RETURN_TYPE(/datum/xenochimera)
	return null

/mob/living/carbon/human/get_xenochimera_state()
	return xenochimera

/// Gives this human the xenochimera state datum (or returns the existing one). Replaces the old xenochimera component load.
/mob/living/carbon/human/proc/add_xenochimera()
	RETURN_TYPE(/datum/xenochimera)
	if(xenochimera)
		return xenochimera
	rel_set(src, nameof(xenochimera), new /datum/xenochimera(src))
	return xenochimera

/// Removes the xenochimera state datum, if any.
/mob/living/carbon/human/proc/remove_xenochimera()
	own_clear(src, nameof(xenochimera), OWN_DELETE)

/// A current-state replay answer; closing the source question keeps the old Current Form default.
/datum/prompt/choice/xenochimera_review
	timeout = 0
	buttons = TRUE
	var/list/answers
	var/answer_key
	var/cancel_default

/mob/living/carbon/human/proc/reconstitute_form_answered(datum/act/request/A)
	var/datum/prompt/choice/xenochimera_review/ask = A.request
	if(!A.answer && !(ask.outcome == REQ_CANCELLED && isnull(ask.value) && !isnull(ask.cancel_default)))
		return
	. = reconstitute_form_answer_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/human/proc/reconstitute_form_answer_apply(datum/act/request/A)
	var/datum/prompt/choice/xenochimera_review/ask = A.request
	ask.answers[ask.answer_key] = A.answer ? ask.value : ask.cancel_default
	return reconstitute_form_stage(ask.answers)

/mob/living/carbon/human/proc/hatch_answered(datum/act/request/A)
	var/datum/prompt/choice/xenochimera_review/ask = A.request
	if(!A.answer && !(ask.outcome == REQ_CANCELLED && isnull(ask.value) && !isnull(ask.cancel_default)))
		return
	. = hatch_answer_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/human/proc/hatch_answer_apply(datum/act/request/A)
	var/datum/prompt/choice/xenochimera_review/ask = A.request
	ask.answers[ask.answer_key] = A.answer ? ask.value : ask.cancel_default
	return hatch_stage(ask.answers)
