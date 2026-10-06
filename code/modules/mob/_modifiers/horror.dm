// These are modifiers used for various spooky areas that are meant to be SCARY and THREATENING.
// Outside of extreme circumstances, these should not be used.
// For the primary effect, if someone is not in one of the below 'redspace_areas' Then they can not have the modifier
// applied to them. This acts as a failsafe from it from accidentally being used outside of events.
// If you DO want to use this for an event, make the event area a child of /redgate or add it to the below areas list.
// These have some extremely spooky effects and players should know about it beforehand.

// REDSPACE AREAS
// This list needs expansion...  Currently, we have very few proper redspace areas.
// Tossing /area/redgate in here as well. Entering one of these areas (unless coded to do such) doesn't apply
// the modifier, but if you're in one of these areas, you'll keep the modifier until you leave.
GLOBAL_LIST_INIT(redspace_areas, list(
	/area/redspace_abduction,
	/area/redgate,
	/area/survivalpod/redspace // Redspace shelters effectively pull a bit of redspace into realspace, so
))

/datum/body_effect/redspace_drain
	tick_interval = 2 SECONDS
	name = "redspace warp"
	desc = "Your body is being slowly sapped of it's lifeforce, being used to fuel this hellish nightmare of a place."

	on_created_text = span_cult("You feel your body slowly being drained and warped")
	on_expired_text = span_notice("Your body feels more normal.")

	stacks = MODIFIER_STACK_EXTEND

	//mob_overlay_state = "redspace_aura" //Let's be secretive~

/datum/body_effect/redspace_drain/can_apply(mob/living/L, suppress_output = TRUE)
	if(ishuman(L) && !HAS_SYNTHETIC_BIOLOGY(L) && L.lastarea && is_type_in_list(L.lastarea, GLOB.redspace_areas))
		return TRUE
	return FALSE

/datum/body_effect/redspace_drain/on_start(mob/living/L)
	var/mob/living/carbon/human/unfortunate_soul = L
	to_chat(unfortunate_soul, span_cult("You feel as if your lifeforce is slowly being rended from your body."))
	if(!unfortunate_soul.has_contagion(/datum/affliction/contagion/fleshy_spread))
		var/datum/affliction/contagion/fleshy_spread/flesh_disease = new /datum/affliction/contagion/fleshy_spread()
		unfortunate_soul.force_contagion(flesh_disease, BP_TORSO)
	return

/datum/body_effect/redspace_drain/on_end(mob/living/L, expired)
	var/mob/living/carbon/human/unfortunate_soul = L
	if(unfortunate_soul.stat == DEAD) //Only care if we're dead.
		handle_corpse(unfortunate_soul)
		var/obj/effect/landmark/drop_point
		drop_point = pick(REGISTRY_MEMBERS(REGISTRY_LATEJOIN)) //Can be changed to whatever exit list you want. By default, uses REGISTRY_MEMBERS(REGISTRY_LATEJOIN)
		if(drop_point)
			unfortunate_soul.forceMove(get_turf(drop_point))
			unfortunate_soul.endurance = max(50, unfortunate_soul.endurance) //If they died, send them back with 50 endurance or their current endurance. Whatever's higher. We're evil, but not mean.
		else
			message_admins("Redspace Drain expired, but no drop point was found, leaving [unfortunate_soul] in limbo. This is a bug. Please report it with this info: redspace_drain/on_end")

/datum/body_effect/redspace_drain/proc/handle_corpse(mob/living/carbon/human/unfortunate_soul)
	return //Specialty stuff to do to a corpse other than teleport them.

/datum/body_effect/redspace_drain/on_check(mob/living/L) //We don't call parent. This doesn't wear off without set conditions.
	if(L.stat == DEAD)
		L.end_body_effect(type, TRUE)
		return
	else if(L.lastarea && !is_type_in_list(L.lastarea, GLOB.redspace_areas))
		L.end_body_effect(type, TRUE)

/datum/body_effect/redspace_drain/on_tick(mob/living/L)
	var/mob/living/carbon/human/unfortunate_soul = L
	if(isbelly(L.loc)) //If you're eaten, let's hold off on doing anything spooky.
		return

	//The dangerous health effects.
	unfortunate_soul.set_nutrition(max(0, unfortunate_soul.nutrition - 5)) //Your nutrition is being sapped faster than usual.
	if(unfortunate_soul.life_tick % 100 == 0)// Once every 100 ticks, we mutate some organs.
		choose_organs(unfortunate_soul)
		become_drippy(unfortunate_soul)
		to_chat(unfortunate_soul, span_cult("You feel as if your organs are crawling around within your body."))

	if(unfortunate_soul.life_tick % 5 == 0) //Once every 5 ticks, we chip away at them.
		unfortunate_soul.drip(1) //Blood trail.
		unfortunate_soul.injure(INJURY_BLUNT, 1) //Small bit of damage
		if(unfortunate_soul.bloodstr.get_reagent_amount(REAGENT_ID_NUMBENZYME) < 2) //We lose all feeling in our body. We can't tell how injured we are.
			unfortunate_soul.bloodstr.add_reagent(REAGENT_ID_NUMBENZYME,1)
	if(unfortunate_soul.life_tick % 20 == 0) //Once every 20 ticks, we permanetly cripple them.
		unfortunate_soul.endurance = max(10, unfortunate_soul.endurance - 1) //Endurance is reduced by 1, but never below 10. This is PERMANENT for the rest of the round or until resleeving.

	//The mental effects.
	unfortunate_soul.set_fear(min(100, unfortunate_soul.fear + 2)) //Fear is increased by 1, but never above 100. You're in a scary place.
	if(unfortunate_soul.life_tick % 20 == 0)
		var/obj/item/organ/O = (length(unfortunate_soul.internal_organ_list()) ? pick(unfortunate_soul.internal_organ_list()) : null)
		if(O) //If you don't have any internal organs, you know what? No spooky messages for you, freak.
			var/spooky_message = pick("Join us...", "Stay with us...", "Stay forever...", "Don't leave us...", \
			"Don't go...", "We can be as one...", "Become one with us...", \
			"You can feel your [O] squirming inside of you, trying to get out...", "Your [O] is trying to escape...", \
			"Your [O] itches.", "Your [O] is crawling around inside of you.")
			to_chat(unfortunate_soul, span_cult(spooky_message))
		unfortunate_soul.status_adjust(STAT_DIZZY, 5)
		unfortunate_soul.status_set(STAT_STUTTERING, min(100, unfortunate_soul.status_units(STAT_STUTTERING) + 10)) //Stuttering is increased by 1, but never above 100. You're in a scary place.
	return

/datum/body_effect/redspace_drain/proc/choose_organs(mob/living/carbon/human/unfortunate_soul, organs_to_replace)
	if(!organs_to_replace)
		organs_to_replace = rand(2,3)
	if(organs_to_replace <= 0) //Sanity
		return
	for(var/i = 0 to organs_to_replace)
		var/organ_choice = pick("eyes", "heart", "lungs", "liver", "kidneys", "appendix", "voicebox", "spleen", "stomach", "intestine")
		switch(organ_choice)
			if("eyes")
				var/obj/item/organ/internal/eyes/E = unfortunate_soul.organ_in(O_EYES)
				if(E)
					replace_eyes(unfortunate_soul, E)
			if("heart")
				var/obj/item/organ/internal/heart/H = unfortunate_soul.organ_in(O_HEART)
				if(H)
					replace_heart(unfortunate_soul, H)
			if("lungs")
				var/obj/item/organ/internal/lungs/L = unfortunate_soul.organ_in(O_LUNGS)
				if(L)
					replace_lungs(unfortunate_soul, L)
			if("liver")
				var/obj/item/organ/internal/liver/L = unfortunate_soul.organ_in(O_LIVER)
				if(L)
					replace_liver(unfortunate_soul, L)
			if("kidneys")
				var/obj/item/organ/internal/kidneys/K = unfortunate_soul.organ_in(O_KIDNEYS)
				if(K)
					replace_kidneys(unfortunate_soul, K)
			if("appendix")
				var/obj/item/organ/internal/appendix/A = unfortunate_soul.organ_in(O_APPENDIX)
				if(A)
					replace_appendix(unfortunate_soul, A)
			if("voicebox")
				var/obj/item/organ/internal/voicebox/V = unfortunate_soul.organ_in(O_VOICE)
				if(V)
					replace_voicebox(unfortunate_soul, V)
			if("spleen")
				var/obj/item/organ/internal/spleen/S = unfortunate_soul.organ_in(O_SPLEEN)
				if(S)
					replace_spleen(unfortunate_soul, S)
			if("stomach")
				var/obj/item/organ/internal/stomach/S = unfortunate_soul.organ_in(O_STOMACH)
				if(S)
					replace_stomach(unfortunate_soul, S)
			if("intestine")
				var/obj/item/organ/internal/intestine/E = unfortunate_soul.organ_in(O_INTESTINE)
				if(E)
					replace_intestine(unfortunate_soul, E)

/datum/body_effect/redspace_drain/proc/replace_eyes(mob/living/carbon/human/unfortunate_soul, obj/item/organ/internal/O)
	if(istype(O, /obj/item/organ/internal/eyes/horror))
		return
	var/organ_spot = O.parent_organ
	var/obj/item/organ/internal/eyes/new_organ = new /obj/item/organ/internal/eyes/horror()
	O.removed(unfortunate_soul)
	replaced_by(O, new_organ)
	new_organ.replaced(unfortunate_soul,unfortunate_soul.get_organ(organ_spot))
	var/random_name = pick("pulsating", "quivering", "throbbing", "crawling", "oozing", "melting", "gushing", "dripping", "twitching", "slimy", "gooey")
	new_organ.name = "[random_name] [initial(new_organ.name)]"

/datum/body_effect/redspace_drain/proc/replace_heart(mob/living/carbon/human/unfortunate_soul, obj/item/organ/internal/O)
	if(istype(O, /obj/item/organ/internal/heart/horror))
		return
	var/organ_spot = O.parent_organ
	var/obj/item/organ/internal/heart/new_organ = new /obj/item/organ/internal/heart/horror()
	O.removed(unfortunate_soul)
	replaced_by(O, new_organ)
	new_organ.replaced(unfortunate_soul,unfortunate_soul.get_organ(organ_spot))
	var/random_name = pick("pulsating", "quivering", "throbbing", "crawling", "oozing", "melting", "gushing", "dripping", "twitching", "slimy", "gooey")
	new_organ.name = "[random_name] [initial(new_organ.name)]"

/datum/body_effect/redspace_drain/proc/replace_lungs(mob/living/carbon/human/unfortunate_soul, obj/item/organ/internal/O)
	if(istype(O, /obj/item/organ/internal/lungs/horror))
		return
	var/organ_spot = O.parent_organ
	var/obj/item/organ/internal/lungs/new_organ = new /obj/item/organ/internal/lungs/horror()
	O.removed(unfortunate_soul)
	spent(O)
	new_organ.replaced(unfortunate_soul,unfortunate_soul.get_organ(organ_spot))
	var/random_name = pick("pulsating", "quivering", "throbbing", "crawling", "oozing", "melting", "gushing", "dripping", "twitching", "slimy", "gooey")
	new_organ.name = "[random_name] [initial(new_organ.name)]"

/datum/body_effect/redspace_drain/proc/replace_liver(mob/living/carbon/human/unfortunate_soul, obj/item/organ/internal/O)
	if(istype(O, /obj/item/organ/internal/liver/horror))
		return
	var/organ_spot = O.parent_organ
	var/obj/item/organ/internal/liver/new_organ = new /obj/item/organ/internal/liver/horror()
	O.removed(unfortunate_soul)
	spent(O)
	new_organ.replaced(unfortunate_soul,unfortunate_soul.get_organ(organ_spot))
	var/random_name = pick("pulsating", "quivering", "throbbing", "crawling", "oozing", "melting", "gushing", "dripping", "twitching", "slimy", "gooey")
	new_organ.name = "[random_name] [initial(new_organ.name)]"

/datum/body_effect/redspace_drain/proc/replace_kidneys(mob/living/carbon/human/unfortunate_soul, obj/item/organ/internal/O)
	if(istype(O, /obj/item/organ/internal/kidneys/horror))
		return
	var/organ_spot = O.parent_organ
	var/obj/item/organ/internal/kidneys/new_organ = new /obj/item/organ/internal/kidneys/horror()
	O.removed(unfortunate_soul)
	spent(O)
	new_organ.replaced(unfortunate_soul,unfortunate_soul.get_organ(organ_spot))
	var/random_name = pick("pulsating", "quivering", "throbbing", "crawling", "oozing", "melting", "gushing", "dripping", "twitching", "slimy", "gooey")
	new_organ.name = "[random_name] [initial(new_organ.name)]"

/datum/body_effect/redspace_drain/proc/replace_appendix(mob/living/carbon/human/unfortunate_soul, obj/item/organ/internal/O)
	if(istype(O, /obj/item/organ/internal/appendix/horror))
		return
	var/organ_spot = O.parent_organ
	var/obj/item/organ/internal/appendix/new_organ = new /obj/item/organ/internal/appendix/horror()
	O.removed(unfortunate_soul)
	spent(O)
	new_organ.replaced(unfortunate_soul,unfortunate_soul.get_organ(organ_spot))
	var/random_name = pick("pulsating", "quivering", "throbbing", "crawling", "oozing", "melting", "gushing", "dripping", "twitching", "slimy", "gooey")
	new_organ.name = "[random_name] [initial(new_organ.name)]"

/datum/body_effect/redspace_drain/proc/replace_voicebox(mob/living/carbon/human/unfortunate_soul, obj/item/organ/internal/O)
	if(istype(O, /obj/item/organ/internal/voicebox/horror))
		return
	var/organ_spot = O.parent_organ
	var/obj/item/organ/internal/voicebox/new_organ = new /obj/item/organ/internal/voicebox/horror()
	O.removed(unfortunate_soul)
	spent(O)
	new_organ.replaced(unfortunate_soul,unfortunate_soul.get_organ(organ_spot))
	var/random_name = pick("pulsating", "quivering", "throbbing", "crawling", "oozing", "melting", "gushing", "dripping", "twitching", "slimy", "gooey")
	new_organ.name = "[random_name] [initial(new_organ.name)]"

/datum/body_effect/redspace_drain/proc/replace_spleen(mob/living/carbon/human/unfortunate_soul, obj/item/organ/internal/O)
	if(istype(O, /obj/item/organ/internal/spleen/horror))
		return
	var/organ_spot = O.parent_organ
	var/obj/item/organ/internal/spleen/new_organ = new /obj/item/organ/internal/spleen/horror()
	O.removed(unfortunate_soul)
	spent(O)
	new_organ.replaced(unfortunate_soul,unfortunate_soul.get_organ(organ_spot))
	var/random_name = pick("pulsating", "quivering", "throbbing", "crawling", "oozing", "melting", "gushing", "dripping", "twitching", "slimy", "gooey")
	new_organ.name = "[random_name] [initial(new_organ.name)]"

/datum/body_effect/redspace_drain/proc/replace_stomach(mob/living/carbon/human/unfortunate_soul, obj/item/organ/internal/O)
	if(istype(O, /obj/item/organ/internal/stomach/horror))
		return
	var/organ_spot = O.parent_organ
	var/obj/item/organ/internal/stomach/new_organ = new /obj/item/organ/internal/stomach/horror()
	O.removed(unfortunate_soul)
	spent(O)
	new_organ.replaced(unfortunate_soul,unfortunate_soul.get_organ(organ_spot))
	var/random_name = pick("pulsating", "quivering", "throbbing", "crawling", "oozing", "melting", "gushing", "dripping", "twitching", "slimy", "gooey")
	new_organ.name = "[random_name] [initial(new_organ.name)]"

/datum/body_effect/redspace_drain/proc/replace_intestine(mob/living/carbon/human/unfortunate_soul, obj/item/organ/internal/O)
	if(istype(O, /obj/item/organ/internal/intestine/horror))
		return
	var/organ_spot = O.parent_organ
	var/obj/item/organ/internal/intestine/new_organ = new /obj/item/organ/internal/intestine/horror()
	O.removed(unfortunate_soul)
	spent(O)
	new_organ.replaced(unfortunate_soul,unfortunate_soul.get_organ(organ_spot))
	var/random_name = pick("pulsating", "quivering", "throbbing", "crawling", "oozing", "melting", "gushing", "dripping", "twitching", "slimy", "gooey")
	new_organ.name = "[random_name] [initial(new_organ.name)]"

///Variant redspace drain ONLY used for the virus.
/datum/body_effect/redspace_drain/lesser
	tick_interval = 2 SECONDS
	name = "redspace infection"
	desc = "Your body is warping..."

	on_created_text = null
	on_expired_text = null

/datum/body_effect/redspace_drain/lesser/can_apply(mob/living/L, suppress_output = TRUE)
	if(ishuman(L) && !HAS_SYNTHETIC_BIOLOGY(L))
		return TRUE
	return FALSE

/datum/body_effect/redspace_drain/lesser/on_start(mob/living/L)
	return

/datum/body_effect/redspace_drain/lesser/on_end(mob/living/L, expired)
	return

/datum/body_effect/redspace_drain/lesser/on_check(mob/living/L)
	return

/datum/body_effect/redspace_drain/lesser/on_tick(mob/living/L)
	return

/datum/body_effect/redspace_drain/proc/become_drippy(mob/living/carbon/human/unfortunate_soul)
	if(!(unfortunate_soul.species.flags & NO_DNA)) //Doing it as such in case drippy is ever made NOT a trait gene.
		var/datum/gene/trait/drippy_trait = get_gene_from_trait(/datum/trait/neutral/drippy)
		unfortunate_soul.dna.SetSEState(drippy_trait.block, TRUE)
		domutcheck(unfortunate_soul, null, GENE_ALWAYS_ACTIVATE)
		unfortunate_soul.UpdateAppearance()

/datum/body_effect/redsight
	tick_interval = 2 SECONDS
	name = "redsight"
	desc = "You can see into the unknown."
	client_color = "#ce6161"

	on_created_text = span_alien("You feel as though you can see the horrors of reality!")
	on_expired_text = span_notice("Your sight returns to what it once was.")
	stacks = MODIFIER_STACK_EXTEND

/datum/body_effect/redsight/on_start(mob/living/L)
	L.see_invisible = 60
	L.set_see_invisible_default(60)
	L.vis_enabled += VIS_GHOSTS
	L.recalculate_vis()

/datum/body_effect/redsight/on_end(mob/living/L, expired)
	L.set_see_invisible_default(initial(L.see_invisible_default))
	L.see_invisible = L.see_invisible_default
	L.vis_enabled -= VIS_GHOSTS
	L.recalculate_vis()

/datum/body_effect/redsight/can_apply(mob/living/L)
	if(L.stat)
		to_chat(L, span_warning("You can't be unconscious or dead to see the unknown."))
		return FALSE
	var/obj/item/organ/internal/eyes/E = L.organ_in(O_EYES)
	if(E && istype(E, /obj/item/organ/internal/eyes/horror))
		return ..()
	return FALSE

/datum/body_effect/redsight/on_check(mob/living/L) //We don't call parent. This doesn't wear off without set conditions.
	//Dead?
	if(L.stat == DEAD)
		L.end_body_effect(type, TRUE)
		return
	//We got eyes and they're special eyes?
	var/obj/item/organ/internal/eyes/E = L.organ_in(O_EYES)
	if(!E)
		L.end_body_effect(type, TRUE)
	else if(!istype(E, /obj/item/organ/internal/eyes/horror))
		L.end_body_effect(type, TRUE)


///The PERMANENT debuff that redspace warp leaves you with.
/datum/body_effect/redspace_corruption
	tick_interval = 2 SECONDS
	name = "redspace corruption"
	desc = "Your body has been permanently twisted."

	on_created_text = null
	on_expired_text = null

	stacks = MODIFIER_STACK_EXTEND

	///Cooldown on how often we can revive.
	var/revival_cooldown = 60 SECONDS

	///How often do we do a 'heal tick' ?
	var/heal_tick_cooldown = 5 SECONDS

	///What chance is there per tick that we unsheath an armblade and face someone?
	var/blade_chance = 1

	///What is the chance that we inject a paralyze a nearby crewmember that is standing too close to us?
	var/injection_chance = 3

	///How long can we upkeep our armor?
	var/armor_duration = 5 MINUTES

/// Per-application state of redspace corruption (body_effect_state() on the corrupted mob).
/datum/redspace_corruption_state
	///Revival lockout after we last revived
	COOLDOWN_DECLARE(revival_cooldown_until)
	///When did we last do a 'heal tick' ?
	COOLDOWN_DECLARE(heal_tick_cooldown_until)
	///If we have our flesh armor deployed or not.
	var/armor_deployed = FALSE
	///When deployed armor expires while alive (armor_duration after deploy)
	COOLDOWN_DECLARE(armor_expire_cooldown)
	///When deployed armor expires while dead (armor_duration * 2 after deploy)
	COOLDOWN_DECLARE(armor_expire_dead_cooldown)
	///What is our hivemind name?
	var/speech_name = "The Unseen Horror"

/// The hivemind name of a corrupted mob, or null when it isn't corrupted.
/mob/living/proc/redspace_speech_name()
	var/datum/redspace_corruption_state/state = body_effect_state(/datum/body_effect/redspace_corruption)
	return state?.speech_name

/datum/body_effect/redspace_corruption/can_apply(mob/living/L, suppress_output = TRUE)
	if(ishuman(L) && !HAS_SYNTHETIC_BIOLOGY(L))
		if(L.mind?.assigned_role == JOB_CHAPLAIN)
			return FALSE
		return TRUE
	return FALSE

/datum/body_effect/redspace_corruption/on_start(mob/living/L)
	var/mob/living/carbon/human/unfortunate_soul = L
	var/datum/redspace_corruption_state/state = new
	L.set_body_effect_state(type, state)
	add_trait(unfortunate_soul, TRAIT_REDSPACE_CORRUPTED, UNHOLY_TRAIT)
	add_trait(unfortunate_soul, UNIQUE_MINDSTRUCTURE, UNHOLY_TRAIT)
	state.speech_name = pick("Lost Soul", "Rescued One", "The Embraced", "The Chosen", "The Unseen Horror", "Obedient Servant", "Willing Follower")

	//SHUNT ALL THE IMPORTANT ORGANS TO THE CHEST!
	var/obj/item/organ/internal/brain/brain = unfortunate_soul.organ_in(O_BRAIN)
	var/obj/item/organ/internal/eyes/eyes = unfortunate_soul.organ_in(O_EYES)
	var/obj/item/organ/external/chest/torso = unfortunate_soul.get_organ(BP_TORSO)
	// Ledger moves from the head's organ slot into the torso's, within the body.
	if(brain && torso && unfortunate_soul.should_have_organ(O_BRAIN))
		brain.parent_organ = BP_TORSO //Move the brain to the torso.
		brain.place_into(torso, SLOT_ID_PART_ORGANS)
	if(eyes && torso && unfortunate_soul.should_have_organ(O_EYES))
		eyes.parent_organ = BP_TORSO //Move the eyes to the torso.
		eyes.place_into(torso, SLOT_ID_PART_ORGANS)
	for(var/obj/item/organ/external/head/ex_organ in unfortunate_soul.organs)
		ex_organ.cannot_break = TRUE
		ex_organ.dislocated = -1
		ex_organ.nonsolid = TRUE
		ex_organ.spread_dam = TRUE
		ex_organ.set_max_damage(5) //VERY fragile, now.
		ex_organ.vital = FALSE
		ex_organ.encased = FALSE
		ex_organ.cannot_gib = FALSE

/datum/body_effect/redspace_corruption/on_end(mob/living/L, expired)
	remove_trait(L, TRAIT_REDSPACE_CORRUPTED, UNHOLY_TRAIT)
	remove_trait(L, UNIQUE_MINDSTRUCTURE, UNHOLY_TRAIT)

/datum/body_effect/redspace_corruption/on_tick(mob/living/L)
	var/mob/living/carbon/human/unfortunate_soul = L
	var/datum/redspace_corruption_state/state = L.body_effect_state(type)
	//Handles resurrection and healing if dead.
	var/bellied = FALSE
	if(isbelly(unfortunate_soul.loc))
		bellied = TRUE
		var/mob/living/carbon/human/predator = unfortunate_soul.loc.loc
		if(istype(predator) && !predator.has_contagion(/datum/affliction/contagion/fleshy_spread))
			var/datum/affliction/contagion/fleshy_spread/flesh_disease = new /datum/affliction/contagion/fleshy_spread()
			predator.force_contagion(flesh_disease, BP_TORSO)

	if(unfortunate_soul.stat == DEAD)
		handle_death(unfortunate_soul, state)
		return

	if(!state.armor_deployed && (unfortunate_soul.has_status(STAT_STUNNED) || unfortunate_soul.has_status(STAT_WEAKENED) || unfortunate_soul.has_status(STAT_PARALYZED) || unfortunate_soul.vitality() < 0.75))
		if(assume_battle_stance(unfortunate_soul, state))
			unfortunate_soul.mend(TREAT_ANALGESIC, 200) //WAKE UP SAMURI
			unfortunate_soul.reagents.add_reagent(REAGENT_ID_ADRENALINE, 5)
			unfortunate_soul.reagents.add_reagent(REAGENT_ID_EPINEPHRINE, 5)
			unfortunate_soul.reagents.add_reagent(REAGENT_ID_NUMBENZYME, 1)
			to_chat(unfortunate_soul, span_large(span_bolddanger("Your body surges with adrenaline, and every cell ignites with a primal fight or flight. Your instincts are screaming through every fiber of your body: Escape the danger. Kill the threats. Protect your body. SURVIVE.")))
			return

	else if(unfortunate_soul.stat == UNCONSCIOUS)
		return

	if(bellied)
		return

	if(state.armor_deployed && COOLDOWN_FINISHED(state, armor_expire_cooldown)) //Time ran out.

		//Are we still in panic mode?
		if(unfortunate_soul.has_status(STAT_STUNNED) || unfortunate_soul.has_status(STAT_WEAKENED) || unfortunate_soul.has_status(STAT_PARALYZED) || (unfortunate_soul.vitality() < 0.75))
			return
		else
			equip_flesh_armor(unfortunate_soul, /obj/item/clothing/suit/space/changeling/armored, /obj/item/clothing/head/helmet/space/changeling/armored, /obj/item/clothing/shoes/magboots/changeling/armored, /obj/item/clothing/gloves/combat/changeling)
			state.armor_deployed = FALSE
		return
	//Stuff that happens when we're ALIVE.
	if(prob(blade_chance))
		//If we have an open hand and we have people near us, unsheath an armblade and face them.
		//This plays a BIG SCARY MESSAGE in chat and will make people panic.
		if(!unfortunate_soul.hands_are_full())
			if(attempt_armblade(unfortunate_soul))
				return
	if(prob(injection_chance))
		var/list_of_humans = list()
		var/prick_message
		for(var/mob/living/carbon/human/target in oview(1, unfortunate_soul.loc))
			if(target.has_body_effect(/datum/body_effect/redspace_corruption)) //No cyclic injections!
				if(!prick_message)
					to_chat(unfortunate_soul, span_warning("Your body stealthily injects [target] but they seem unaffected."))
					to_chat(target, span_bolddanger("You feel a tiny prick."))
					prick_message = TRUE
				continue
			if(is_changeling(target))
				if(!prick_message)
					to_chat(unfortunate_soul, span_warning("Your body stealthily injects [target] but they seem unaffected."))
					to_chat(target, span_bolddanger("You feel a tiny prick."))
					prick_message = TRUE
				continue
			list_of_humans += target
		if(LAZYLEN(list_of_humans))
			var/mob/living/carbon/human/prey = pick(list_of_humans)
			if(!prey)
				return
			to_chat(prey, span_bolddanger("You feel a tiny prick."))
			prey.reagents.add_reagent(REAGENT_ID_ZOMBIEPOWDER, 5)
			if(!prey.has_contagion(/datum/affliction/contagion/fleshy_spread))
				var/datum/affliction/contagion/fleshy_spread/flesh_disease = new /datum/affliction/contagion/fleshy_spread()
				prey.force_contagion(flesh_disease)
			to_chat(unfortunate_soul, span_warning("[prey] walks too close to you, your body instinctually stinging them"))

	return

/datum/body_effect/redspace_corruption/proc/handle_death(mob/living/carbon/human/unfortunate_soul, datum/redspace_corruption_state/state)

	//Cooldown?

	if(state.armor_deployed && COOLDOWN_FINISHED(state, armor_expire_dead_cooldown)) //Takes longer for armor to undeploy when dead.
		exit_battle_stance(unfortunate_soul, state)

	if(!COOLDOWN_FINISHED(state, heal_tick_cooldown_until))
		return

	var/obj/item/organ/internal/brain/brain = unfortunate_soul.organ_in(O_BRAIN)
	if(unfortunate_soul.should_have_organ(O_BRAIN))
		if(!brain) //Removed the brain? Can't do anything.
			return

	var/obj/item/organ/internal/heart/heart = unfortunate_soul.organ_in(O_HEART)
	if(!heart)
		return

	var/blood_volume = unfortunate_soul.vessel.get_reagent_amount(REAGENT_ID_BLOOD)
	var/lethal_blood = FALSE
	if(unfortunate_soul.reagents.get_reagent_amount(REAGENT_ID_MYELAMINE) < 5)
		unfortunate_soul.reagents.add_reagent(REAGENT_ID_MYELAMINE, 5) //Helps stabilize them.
	if(!heart || heart.is_broken())
		blood_volume *= 0.3
	else if(heart.is_bruised())
		blood_volume *= 0.7
	else if(heart.damage > 1)
		blood_volume *= 0.8
	if(blood_volume < unfortunate_soul.species.blood_volume*unfortunate_soul.species.blood_level_fatal)
		unfortunate_soul.reagents.add_reagent(REAGENT_ID_SYNTHBLOOD, 25) //Will get processed below.
		lethal_blood = TRUE

	//Circulate chems.
	for(var/i in 1 to 5)
		unfortunate_soul.process_chemicals()
	unfortunate_soul.organs_advance(1)

	//Slowly come back from the dead.
	unfortunate_soul.mend(TREAT_TISSUE_REPAIR, 2)
	unfortunate_soul.mend(TREAT_BURN_CARE, 2)
	unfortunate_soul.mend(TREAT_ANTITOXIN, 5)
	unfortunate_soul.mend(TREAT_OXYGENATION, 5)
	unfortunate_soul.mend(TREAT_NEURAL_REPAIR, 0.5)

	//Handle our organs. We might not heal entirely before we come back, but that's fine. If we die again, we come back again.
	for(var/obj/item/organ/internal/I in unfortunate_soul.internal_organ_list())
		I.periodic_step()
		I.germ_level = max(0, I.germ_level - 25)
		unfortunate_soul.mend(TREAT_RESTORATION, 2.5, I)
		if(I.status & ORGAN_DEAD && (I.damage < I.is_broken()) && (I.germ_level < INFECTION_LEVEL_ONE)) //If we have any dead organs, try to revive them.
			I.restore_status()

	for(var/obj/item/organ/external/limb in unfortunate_soul.damaged_limbs())
		limb.germ_level = max(0, limb.germ_level - 25)
		if(limb.status & ORGAN_DEAD && (limb.damage < limb.is_broken()) && (limb.germ_level < INFECTION_LEVEL_ONE)) //If we have any dead organs, try to revive them.
			limb.set_status(0)

	COOLDOWN_START(state, heal_tick_cooldown_until, heal_tick_cooldown)

	//Big checks to see if there's a reason we CAN'T revive.
	if(!COOLDOWN_FINISHED(state, revival_cooldown_until)) //On cooldown.
		return
	if(lethal_blood) //Blood volume is low enough we'd immediately die upon revival.
		return
	if(unfortunate_soul.can_return_from_death(REVIVE_IGNORE_WINDOW) || unfortunate_soul.vitality() <= VITALITY_SERIOUS) //Too injured to revive. We want to be a bit JUST before hardcrit.
		return
	if(unfortunate_soul.check_vital_organs()) //Missing a vital organ.
		return
	if(unfortunate_soul.teleop) //Aghosted or the sort.
		return
	if(!unfortunate_soul.mind) //Mind is gone.
		return

	//This won't get EVERYTHING, but if we end up reviving just to die shortly afterwards to heal up further, that's fine.

	//Time to revive! This FORCIBLY grabs their mind and puts it back in.
	revive(unfortunate_soul, state)
	return

/datum/body_effect/redspace_corruption/proc/revive(mob/living/carbon/human/unfortunate_soul, datum/redspace_corruption_state/state)
	//Force us back into the body.
	unfortunate_soul.grab_ghost(TRUE)

	if(unfortunate_soul.return_from_death("redspace corruption", src, REVIVE_IGNORE_WINDOW | REVIVE_UNCONSCIOUS) != TRUE)
		return

	//Awaken!
	unfortunate_soul.emote("gasp")
	unfortunate_soul.status_at_least(STAT_WEAKENED, rand(10,25))
	COOLDOWN_START(state, revival_cooldown_until, revival_cooldown)

//Returns TRUE If we succeeded. FALSE if we failed.
/datum/body_effect/redspace_corruption/proc/attempt_armblade(mob/living/carbon/human/unfortunate_soul)
	var/list_of_humans = list()
	for(var/mob/living/carbon/human/target in oview(4, unfortunate_soul.loc))
		if(target.has_body_effect(/datum/body_effect/redspace_corruption)) //Flesh knows flesh.
			continue
		if(is_changeling(target))
			continue
		list_of_humans += target
	if(LAZYLEN(list_of_humans))
		var/mob/person_to_stare_at_with_our_special_eyes = pick(list_of_humans)
		if(!person_to_stare_at_with_our_special_eyes)
			return FALSE
		deploy_armblade(unfortunate_soul)
		unfortunate_soul.face_atom(person_to_stare_at_with_our_special_eyes)
		if(get_dist(unfortunate_soul, person_to_stare_at_with_our_special_eyes.loc) > 1)
			step_towards(unfortunate_soul, person_to_stare_at_with_our_special_eyes)
		if(get_dist(unfortunate_soul, person_to_stare_at_with_our_special_eyes.loc) > 1)
			step_towards(unfortunate_soul, person_to_stare_at_with_our_special_eyes)
		return TRUE
	return FALSE

/datum/body_effect/redspace_corruption/proc/deploy_armblade(mob/living/carbon/human/unfortunate_soul)
	var/obj/item/melee/changeling/arm_blade/blade = new /obj/item/melee/changeling/arm_blade(unfortunate_soul)
	if(!unfortunate_soul.put_in_hands(blade))
		spent(blade) //failed, sad.

//shamelessly stolen from changeling/armor.dm
/datum/body_effect/redspace_corruption/proc/equip_flesh_armor(mob/living/carbon/human/unfortunate_soul, armor_type, helmet_type, boot_type, glove_type)

	var/mob/living/carbon/human/M = unfortunate_soul

	//First, check if we're already wearing the armor, and if so, take it off.
	if(istype(M.get_equipped_item(SLOT_ID_SUIT), armor_type) || istype(M.get_equipped_item(SLOT_ID_HEAD), helmet_type) || istype(M.get_equipped_item(SLOT_ID_SHOES), boot_type) || istype(M.get_equipped_item(SLOT_ID_GLOVES), glove_type))
		act_message(M, null, MSG_SELF(span_warning("We cast off our [M.get_equipped_item(SLOT_ID_SUIT) ? M.get_equipped_item(SLOT_ID_SUIT).name : "armor"]")), \
			MSG_OTHERS(span_warning("%U% casts off their [M.get_equipped_item(SLOT_ID_SUIT) ? M.get_equipped_item(SLOT_ID_SUIT).name : "armor"]!")), \
			MSG_BLIND(span_warningplain("You hear the organic matter ripping and tearing!")))
		if(istype(M.get_equipped_item(SLOT_ID_SUIT), armor_type))
			M.slot_clear(SLOT_ID_SUIT)
		if(istype(M.get_equipped_item(SLOT_ID_HEAD), helmet_type))
			M.slot_clear(SLOT_ID_HEAD)
		if(istype(M.get_equipped_item(SLOT_ID_SHOES), boot_type))
			M.slot_clear(SLOT_ID_SHOES)
		if(istype(M.get_equipped_item(SLOT_ID_GLOVES), glove_type))
			M.slot_clear(SLOT_ID_GLOVES)
		M.update_inv_wear_suit()
		M.update_inv_head()
		M.update_hair()
		M.update_inv_shoes()
		M.update_inv_gloves()
		return TRUE

	var/obj/item/clothing/suit/A = new armor_type(M)
	if(M.get_equipped_item(SLOT_ID_SUIT))
		M.unEquip(M.get_equipped_item(SLOT_ID_SUIT), TRUE)
	M.equip_to_slot_or_del(A, SLOT_ID_SUIT)

	var/obj/item/clothing/suit/H = new helmet_type(M)
	if(M.get_equipped_item(SLOT_ID_HEAD))
		M.unEquip(M.get_equipped_item(SLOT_ID_HEAD), TRUE)
	M.equip_to_slot_or_del(H, SLOT_ID_HEAD)

	var/obj/item/clothing/shoes/B = new boot_type(M)
	if(M.get_equipped_item(SLOT_ID_SHOES))
		M.unEquip(M.get_equipped_item(SLOT_ID_SHOES), TRUE)
	M.equip_to_slot_or_del(B, SLOT_ID_SHOES)

	var/obj/item/clothing/gloves/G = new glove_type(M)
	if(M.get_equipped_item(SLOT_ID_GLOVES))
		M.unEquip(M.get_equipped_item(SLOT_ID_GLOVES), TRUE)
	M.equip_to_slot_or_del(G, SLOT_ID_GLOVES)

	play_sfx(M, SFX_EFFECTS_BLOBATTACK)
	M.update_inv_wear_suit()
	M.update_inv_head()
	M.update_hair()
	M.update_inv_shoes()
	M.update_inv_gloves()
	return TRUE

///Equips armor and melee weapon. If we succeed, returns TRUE. FALSE if we fail.
/datum/body_effect/redspace_corruption/proc/assume_battle_stance(mob/living/carbon/human/unfortunate_soul, datum/redspace_corruption_state/state)
	if(equip_flesh_armor(unfortunate_soul, /obj/item/clothing/suit/space/changeling/armored,/obj/item/clothing/head/helmet/space/changeling/armored,/obj/item/clothing/shoes/magboots/changeling/armored, /obj/item/clothing/gloves/combat/changeling))
		to_chat(unfortunate_soul, span_warning("Your flesh shifts and hardens into a protective armor!"))
		state.armor_deployed = TRUE
		COOLDOWN_START(state, armor_expire_cooldown, armor_duration)
		COOLDOWN_START(state, armor_expire_dead_cooldown, armor_duration * 2)
		unfortunate_soul.drop_l_hand()
		unfortunate_soul.drop_r_hand()
		deploy_armblade(unfortunate_soul)
		deploy_armblade(unfortunate_soul)
		return TRUE
	return FALSE

/datum/body_effect/redspace_corruption/proc/exit_battle_stance(mob/living/carbon/human/unfortunate_soul, datum/redspace_corruption_state/state)
	if(state.armor_deployed)
		equip_flesh_armor(unfortunate_soul, /obj/item/clothing/suit/space/changeling/armored, /obj/item/clothing/head/helmet/space/changeling/armored, /obj/item/clothing/shoes/magboots/changeling/armored, /obj/item/clothing/gloves/combat/changeling)
		state.armor_deployed = FALSE
		unfortunate_soul.drop_l_hand()
		unfortunate_soul.drop_r_hand()
